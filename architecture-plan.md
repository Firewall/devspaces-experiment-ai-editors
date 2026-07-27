# T3 Code as a Native Dev Spaces Editor

## Overview

The goal is to integrate **T3 Code** into **Red Hat OpenShift Dev Spaces** as a first-class editor, rather than simply running it as another application inside a workspace.

Instead of users manually installing and launching T3 Code, it becomes selectable alongside existing editors such as Che Code.

The architecture leverages:

- OpenShift Dev Spaces  
- Eclipse Che Editor Definitions  
- T3 Code  
- Claude Code  
- Google Vertex AI (enterprise managed)

---

# High-Level Architecture

```
                 Dev Spaces Dashboard
                         |
                         |
              Select Editor: "T3 Code"
                         |
                         v

              Eclipse Che Workspace

        +--------------------------------+
        |                                |
        |  T3 Code Editor Container      |
        |                                |
        |  - T3 Web UI                   |
        |  - Claude Code CLI             |
        |  - gcloud CLI                  |
        |                                |
        +---------------+----------------+
                        |
                        |
              Vertex AI Authentication
                        |
                        v

                Google Vertex AI
                        |
                        v

                    Claude
```

---

# Findings

## 1\. T3 Code fits the Che Editor model

T3 Code is a web application that can run inside a container and expose a browser UI.

This matches the Eclipse Che editor architecture well.

Rather than creating a helper container and launching T3 manually, the cleaner approach is to package it as a **Che Editor Definition**.

---

## 2\. Dev Spaces already supports custom editors

Dev Spaces (Eclipse Che) supports registering custom editors through editor definitions.

An editor is simply:

- A container image  
- A Devfile definition  
- One or more exposed endpoints  
- Registered through the Che editor registry

This means T3 Code can appear alongside Che Code as a selectable editor.

---

## 3\. Authentication should remain enterprise-managed

The editor should **not** manage API keys.

Instead, rely on the existing enterprise authentication model.

```
Developer
      │
      ▼
OpenShift Authentication
      │
      ▼
Service Account / Workload Identity
      │
      ▼
Google Vertex AI
      │
      ▼
Claude
```

The editor simply uses Application Default Credentials already available inside the workspace.

---

# Proposed Architecture

## Custom Editor Definition

Create a Devfile describing the editor using the Che three-component pattern:
an **injector** init container, a **runtime description** that merges into the
user's dev container, and a **shared volume** that bridges them.

Register the devfile as a ConfigMap with the required labels:

```
app.kubernetes.io/part-of: che.eclipse.org
app.kubernetes.io/component: editor-definition
```

```
schemaVersion: 2.2.2

metadata:
  name: t3-code/t3-code-editor/latest
  displayName: T3 Code + Claude
  description: AI-native coding environment powered by Claude on Vertex AI
  attributes:
    publisher: t3-code
    version: latest
    title: T3 Code + Claude — AI-native coding on Vertex AI
    firstPublicationDate: '2025-01-01'
    repository: https://github.com/pingdotgg/t3code

commands:
  - id: init-t3-code-injector
    apply:
      component: t3-code-injector
  - id: init-t3-code-start
    exec:
      component: t3-code-runtime
      commandLine: >-
        nohup /t3code/entrypoint.sh > /t3code/entrypoint-logs.txt 2>&1 &

events:
  preStart:
    - init-t3-code-injector
  postStart:
    - init-t3-code-start

components:
  # 1. Injector — copies T3 Code + Claude Code + gcloud into the shared volume
  - name: t3-code-injector
    container:
      image: quay.io/my-org/devspaces-t3-code-editor:latest
      command:
        - /entrypoint-init-container.sh
      volumeMounts:
        - name: t3code
          path: /t3code
      memoryLimit: 256Mi
      memoryRequest: 32Mi
      cpuLimit: 500m
      cpuRequest: 30m

  # 2. Runtime description — merged into the user's dev container
  - name: t3-code-runtime
    container:
      image: quay.io/devfile/universal-developer-image:latest
      env:
        - name: CLAUDE_CODE_USE_VERTEX
          value: "1"
        - name: GOOGLE_CLOUD_PROJECT
          value: "my-project"
        - name: CLOUD_ML_REGION
          value: "us-central1"
      volumeMounts:
        - name: t3code
          path: /t3code
      memoryLimit: 2048Mi
      memoryRequest: 512Mi
      cpuLimit: 1000m
      cpuRequest: 100m
      endpoints:
        - name: t3-code
          targetPort: 3773
          exposure: public
          protocol: https
          secure: true
          attributes:
            type: main
            cookiesAuthEnabled: true
            discoverable: false
            urlRewriteSupported: true
    attributes:
      app.kubernetes.io/component: t3-code-runtime
      app.kubernetes.io/part-of: t3-code.eclipse.org
      controller.devfile.io/container-contribution: true

  # 3. Shared volume between injector and runtime
  - name: t3code
    volume: {}
```

Notes:

- `controller.devfile.io/container-contribution: true` causes the runtime
  component to be merged into the user's dev container at workspace start.
- `mountSources` is NOT needed here — it is inherited from the user's
  workspace devfile through the container-contribution merge.
- `cookiesAuthEnabled: true` auto-redirects unauthenticated requests.
- Port **3773** is the T3 Code default.
- The DevWorkspace Operator polls the editor endpoint to detect readiness;
  no explicit Kubernetes probes are needed in the devfile.
- Memory for the runtime is set higher than che-code (2048Mi vs 1024Mi)
  because Claude Code can be memory-intensive.

---

# Editor Image

Build a dedicated editor image based on UBI9 with Node.js 22.

T3 Code requires Node.js ^22.16 || ^23.11 || >=24.10.

The npm package is `t3` (repo: github.com/pingdotgg/t3code).

```
FROM registry.access.redhat.com/ubi9/nodejs-22 AS builder

USER 0

RUN dnf install -y git && dnf clean all

# Install Google Cloud CLI via Google's yum repo
RUN tee /etc/yum.repos.d/google-cloud-sdk.repo << 'EOM'
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM

RUN CLOUDSDK_SKIP_PY_COMPILATION=1 dnf install -y google-cloud-cli \
    && dnf clean all

# Install T3 Code and Claude Code
RUN npm install -g t3 @anthropic-ai/claude-code

# Copy entrypoints
COPY entrypoint.sh /t3code/entrypoint.sh
COPY entrypoint-init-container.sh /entrypoint-init-container.sh

# OpenShift arbitrary UID support:
# All writable paths must be group-owned by GID 0 and group-writable.
# OpenShift injects a random UID in GID 0 at runtime.
RUN chgrp -R 0 /t3code /opt/app-root && \
    chmod -R g=u /t3code /opt/app-root && \
    chmod g=u /etc/passwd

USER 1001

CMD ["/t3code/entrypoint.sh"]
```

The image contains everything required to launch immediately.

No runtime installation should be necessary.

Two entrypoints are needed:

- `entrypoint-init-container.sh` — copies T3 Code, Claude Code, and gcloud
  binaries into the shared `/t3code` volume during the Che preStart phase.
- `entrypoint.sh` — starts `t3 serve` during the Che postStart phase.

---

# Entrypoints

## Init Container Entrypoint

Copies editor binaries into the shared volume during Che preStart.

```shell
#!/bin/bash
# entrypoint-init-container.sh
set -e

cp -r /opt/app-root/src/node_modules /t3code/node_modules
cp -r /usr/lib/google-cloud-sdk /t3code/google-cloud-sdk

echo "T3 Code injector complete"
```

## Runtime Entrypoint

Starts T3 Code during Che postStart.

```shell
#!/bin/bash
# entrypoint.sh
set -e

# Handle OpenShift arbitrary UID
if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    echo "default:x:$(id -u):0:default user:${HOME}:/sbin/nologin" >> /etc/passwd
  fi
fi

export CLAUDE_CODE_USE_VERTEX=true
export PATH="/t3code/google-cloud-sdk/bin:${PATH}"

cd ${PROJECTS_ROOT:-/projects}

exec t3 serve \
  --host 0.0.0.0 \
  --port 3773 \
  --no-browser
```

Notes:

- `t3 serve` is the headless/server mode designed for remote and container use.
- Port **3773** is the T3 Code default (not 3000 as originally assumed).
- `--no-browser` prevents the server from trying to open a browser.
- The arbitrary UID handler injects the runtime UID into `/etc/passwd` so
  tools that call `whoami` or read `$HOME` work correctly.
- `${PROJECTS_ROOT}` is set by Dev Spaces (defaults to `/projects`).

---

# Registering the Editor

Register the editor by creating a ConfigMap containing the devfile YAML in the
Dev Spaces namespace, then labeling it for discovery.

```shell
# Create the ConfigMap from the devfile
oc create configmap t3-code-editor-definition \
  --from-file=t3-code-editor-devfile.yaml \
  -n openshift-devspaces

# Label for Che Dashboard discovery
oc label configmap t3-code-editor-definition \
  app.kubernetes.io/part-of=che.eclipse.org \
  app.kubernetes.io/component=editor-definition \
  -n openshift-devspaces
```

The Che Dashboard discovers editors by querying ConfigMaps with these two
labels. Once applied, the editor appears in the editor selection UI and is
accessible via the API at:

```
https://<che_fqdn>/dashboard/api/editors
```

A specific editor definition can be fetched at:

```
https://<che_fqdn>/dashboard/api/editors/devfile?che-editor=t3-code/t3-code-editor/latest
```

---

# User Experience

Creating a workspace becomes:

```
Create Workspace

Stack:
  Node.js

Editor:

○ Che Code
○ VS Code
○ JetBrains
● T3 Code + Claude

Create
```

After the workspace starts:

- T3 Code is already running  
- Claude Code is installed  
- Vertex AI authentication is already configured  
- The browser opens directly into T3 Code

No terminal commands are required.

---

# Authentication Flow

The authentication model should remain entirely enterprise managed.

```
Developer
      │
      ▼
OpenShift Login
      │
      ▼
Workspace Service Account
      │
      ▼
Google Application Default Credentials
      │
      ▼
Vertex AI
      │
      ▼
Claude
```

The editor only requires:

```
CLAUDE_CODE_USE_VERTEX=true
```

No API keys should be stored inside the workspace.

---

# MVP Plan

## Phase 1 — Developer Prototype

Goal:

Prove that T3 Code can function as a native Dev Spaces editor.

Deliverables:

- Custom editor container  
- Editor definition  
- Automatic startup  
- Browser endpoint  
- Claude Code using Vertex AI

Expected effort:

A few days.

---

## Phase 2 — Dev Spaces Integration

Integrate the editor into Dev Spaces.

Deliverables:

- Editor icon  
- Registry entry  
- Documentation  
- Support in common language stacks (Node, Java, Python, Go)

Result:

Users can simply choose **T3 Code** when creating a workspace.

---

## Phase 3 — Enterprise Hardening

Add production features.

Examples:

- Resource limits  
- Network policies  
- Audit logging  
- Model selection  
- Vertex AI quotas  
- Workspace health checks

---

# Technical Reference

Key details confirmed through research (July 2025).

## T3 Code

- npm package: `t3` (repo: github.com/pingdotgg/t3code)
- Maintainers: juliusmarminge, t3dotgg (Theo / ping.gg)
- Current version: 0.0.28
- Node.js requirement: `^22.16 || ^23.11 || >=24.10`
- Headless mode: `t3 serve` (see REMOTE.md in the repo)
- Default port: 3773
- Key flags: `--host`, `--port`, `--no-browser`, `--auth-token`, `--mode web`
- Claude integration: via `@anthropic-ai/claude-agent-sdk` dependency
- Full devcontainer support is an open upstream request (issue #2310)

## Che Editor Architecture

Che editors use a three-component pattern:

1. **Injector** (init container) — copies binaries into a shared volume
2. **Runtime description** — merged into the user's dev container via
   `controller.devfile.io/container-contribution: true`
3. **Shared volume** — bridges injector and runtime

The runtime component is NOT a standalone container. The DevWorkspace Operator
merges it into the user's container, preserving the user's image but injecting
the editor's endpoints, env vars, volume mounts, and startup commands.

Health detection: DWO polls the editor endpoint (no Kubernetes probes needed).

## Resource Baselines (from che-code)

| Component | memoryLimit | memoryRequest | cpuLimit | cpuRequest |
|---|---|---|---|---|
| Injector | 256Mi | 32Mi | 500m | 30m |
| Runtime (che-code) | 1024Mi | 256Mi | 500m | 30m |
| Runtime (t3-code, proposed) | 2048Mi | 512Mi | 1000m | 100m |

T3 Code runtime is set higher because Claude Code can be memory-intensive.

## Known Risks

- `t3 serve` works for remote access but full devcontainer integration is not
  yet a native feature upstream. The server mode should be sufficient for MVP.
- The init container / volume injection pattern adds complexity compared to a
  simple single-container approach, but it is the standard Che way and enables
  proper container-contribution merging.
- T3 Code is at version 0.0.28 — expect breaking changes. Pin versions in the
  Dockerfile and test upgrades before rolling out.

---

# Future Opportunities

Once the editor integration works, additional capabilities become possible:

- Automatically open the T3 UI after workspace creation  
- Health monitoring through Dev Spaces  
- Workspace templates with T3 Code as the default editor  
- Multiple AI providers in the future (while keeping Vertex AI as the enterprise default)  
- Integration with Dev Spaces dashboard actions

---

# Strategic Value

This demonstrates more than simply running an AI coding tool inside a container.

It positions Dev Spaces as a platform for **AI-native development environments**.

Instead of treating AI as an IDE extension, the workspace becomes the secure execution environment where:

- Source code lives  
- AI agents execute  
- Enterprise authentication is enforced  
- Infrastructure access remains controlled

The editor itself becomes interchangeable while the enterprise platform remains consistent, aligning well with the direction of modern cloud-based development environments.  
