# AI Editors — Dev Spaces

Packages AI-native code editors as native OpenShift Dev Spaces editors alongside Che Code.

| Editor | AI Backend | Port | Auth |
|--------|-----------|------|------|
| [T3 Code](https://github.com/pingdotgg/t3code) | Claude (Vertex AI) | 3773 | Pairing token |
| [OpenChamber](https://github.com/openchamber/openchamber) | 75+ providers via [OpenCode](https://opencode.ai) | 3000 | UI password |

See [architecture-plan.md](architecture-plan.md) for the full architecture and design rationale.

## Prerequisites

- `podman` (or `docker`)
- `oc` CLI authenticated to the Dev Spaces cluster
- A container registry you can push to (the image must be **public** — Dev Spaces needs to pull it and you likely can't create image pull secrets on shared clusters)
- Google Vertex AI project with Claude enabled (T3 Code; optional for OpenChamber)

## Configuration

Copy the example config and fill in your values:

```bash
cp config.env.example config.env
vi config.env
```

```env
# --- T3 Code ---
T3_IMAGE=quay.io/my-org/devspaces-t3-code-editor:latest

# --- OpenChamber ---
OPENCHAMBER_IMAGE=quay.io/my-org/devspaces-openchamber-editor:latest
# OPENCHAMBER_UI_PASSWORD=my-password  # auto-generated if omitted

# --- Shared ---
NAMESPACE=openshift-devspaces
GOOGLE_CLOUD_PROJECT=my-project
CLOUD_ML_REGION=us-central1
```

`config.env` is gitignored — your settings stay local. Set `NAMESPACE` to your Dev Spaces user namespace (e.g. `rh-ee-yourname-dev`).

## Quick Start — T3 Code (no admin required)

```bash
cp config.env.example config.env
vi config.env
./deploy.sh
```

Prints the T3 Code URL and pairing token when done. Tear down: `./teardown.sh`

## Quick Start — OpenChamber (no admin required)

```bash
cp config.env.example config.env
vi config.env
./deploy-openchamber.sh
```

Prints the OpenChamber URL and UI password when done. Tear down: `./teardown-openchamber.sh`

OpenChamber supports 75+ LLM providers (Anthropic, OpenAI, Google, local models, etc.) via [OpenCode](https://opencode.ai). Configure your provider by shelling into the workspace and editing `~/.config/opencode/config.json`. For Vertex AI, also run `gcloud auth application-default login`.

## What the deploy scripts do

Both `deploy.sh` (T3 Code) and `deploy-openchamber.sh` (OpenChamber) follow the same steps:

1. Build the container image for `linux/amd64` and push to your registry
2. Create a `DevWorkspaceTemplate` (the editor definition) in your namespace
3. Create a `DevWorkspace` that references the editor template
4. Wait for the workspace pod to be ready
5. Create a direct OpenShift Route (bypasses the Che gateway — see "Known Issues")
6. Print the URL and credentials (pairing token for T3 Code, UI password for OpenChamber)

## Authentication

### T3 Code — Pairing Token

T3 Code requires a one-time pairing token on first connect. The deploy script prints it automatically. To retrieve it later:

```bash
POD=$(oc get pods -n <your-namespace> -l controller.devfile.io/devworkspace_name=t3-code-workspace --no-headers | grep -v cleanup | awk '{print $1}')
oc exec $POD -c t3-code-runtime -n <your-namespace> -- cat /projects/.devspaces-t3code/pairing-token.txt
```

### OpenChamber — UI Password

OpenChamber uses a UI password. If not set in `config.env`, one is auto-generated on first start. To retrieve it:

```bash
POD=$(oc get pods -n <your-namespace> -l controller.devfile.io/devworkspace_name=openchamber-workspace --no-headers | grep -v cleanup | awk '{print $1}')
oc exec $POD -c openchamber-runtime -n <your-namespace> -- cat /projects/.devspaces-openchamber/ui-password.txt
```

## LLM Provider Setup

### T3 Code (Vertex AI)

Shell into the pod and authenticate with gcloud:

```bash
POD=$(oc get pods -n <your-namespace> -l controller.devfile.io/devworkspace_name=t3-code-workspace --no-headers | grep -v cleanup | awk '{print $1}')
oc exec -it $POD -c t3-code-runtime -n <your-namespace> -- bash
export PATH=/t3code/npm-global/bin:/t3code/google-cloud-sdk/bin:$PATH
gcloud auth application-default login --no-launch-browser
```

### OpenChamber (any provider)

OpenChamber supports 75+ LLM providers via OpenCode. Shell in and configure:

```bash
POD=$(oc get pods -n <your-namespace> -l controller.devfile.io/devworkspace_name=openchamber-workspace --no-headers | grep -v cleanup | awk '{print $1}')
oc exec -it $POD -c openchamber-runtime -n <your-namespace> -- bash
# Edit OpenCode config with your API key
vi ~/.config/opencode/config.json
# For Vertex AI, also run:
export PATH=/openchamber/npm-global/bin:/openchamber/google-cloud-sdk/bin:$PATH
gcloud auth application-default login --no-launch-browser
```

All credentials are persisted to the `/projects` volume — you only need to do this once per workspace lifetime.

## Cluster-wide Registration (requires admin)

Register editors in the dashboard editor picker for all users:

```bash
# T3 Code
make register

# OpenChamber
make oc-register
```

To remove: `make unregister` / `make oc-unregister`.

## Known Issues

### Both editors

- **Subpath routing** — The Che gateway serves editors under a subpath (e.g. `/username/workspace/port/`). Both editors' assets use absolute paths which break under subpath routing. The deploy scripts work around this by creating a direct Route with its own hostname.
- **Dashboard "Open" button** — May show "workspace has not received an IDE URL". Use the direct Route URL printed by the deploy script instead.
- **ECONNRESET crashes** — The Che gateway probes editor ports, causing unhandled `ECONNRESET` errors that crash Node.js. Both entrypoints include a restart loop that recovers in 2 seconds.
- **Architecture** — Images must be built for `linux/amd64`. Building on ARM requires `--platform linux/amd64` (emulated, slower).
- **gcloud CLI** — Installed via tarball (no `install.sh`) because UBI9 ships Python 3.9 and the latest gcloud installer requires 3.10+.

### T3 Code

- **Upstream issue** — Subpath routing: [#2310](https://github.com/pingdotgg/t3code/issues/2310).
- **Version** — T3 Code is at v0.0.x. Expect breaking changes.

### OpenChamber

- **Theme** — A pre-seeded Red Hat Dark theme is available. Activate via Settings → Theme → Reload themes → "Red Hat Dark".
- **LLM provider** — OpenCode must be configured with an API key after first start. Shell in and edit `~/.config/opencode/config.json`, or use `gcloud auth` for Vertex AI.

## Files

### T3 Code

| File | Purpose |
|------|---------|
| `deploy.sh` | One-command deploy: build, push, create workspace, create route |
| `teardown.sh` | Remove all workspace resources |
| `Containerfile` | Editor image (UBI9 + Node.js 22 + T3 Code + Claude Code + gcloud) |
| `entrypoint.sh` | Runtime startup with auto-restart and persistent pairing token |
| `entrypoint-init-container.sh` | Init container — copies binaries into shared volume |
| `t3-code-editor-devfile.yaml` | Che editor definition template |

### OpenChamber

| File | Purpose |
|------|---------|
| `deploy-openchamber.sh` | One-command deploy: build, push, create workspace, create route |
| `teardown-openchamber.sh` | Remove all workspace resources |
| `Containerfile.openchamber` | Editor image (UBI9 + OpenChamber + OpenCode + gcloud) |
| `entrypoint-openchamber.sh` | Runtime startup with auto-restart and persistent UI password |
| `entrypoint-init-container-openchamber.sh` | Init container — copies binaries into shared volume |
| `openchamber-editor-devfile.yaml` | Che editor definition template |

### Shared

| File | Purpose |
|------|---------|
| `config.env.example` | Template for local `config.env` (both editors) |
| `Makefile` | Build, push, and cluster-wide registration for both editors |
| `architecture-plan.md` | Full architecture plan |
