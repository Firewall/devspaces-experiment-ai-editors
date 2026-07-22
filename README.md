# T3 Code — Dev Spaces Editor

Packages [T3 Code](https://github.com/pingdotgg/t3code) as a native OpenShift Dev Spaces editor alongside Che Code.

See [devspace-t3code-plan.md](devspace-t3code-plan.md) for the full architecture and design rationale.

## Prerequisites

- `podman` (or `docker`)
- `oc` CLI authenticated to the Dev Spaces cluster
- A container registry you can push to (the image must be **public** — Dev Spaces needs to pull it and you likely can't create image pull secrets on shared clusters)
- Google Vertex AI project with Claude enabled

## Configuration

Copy the example config and fill in your values:

```bash
cp config.env.example config.env
vi config.env
```

```env
IMAGE=quay.io/my-org/devspaces-t3-code-editor:latest
NAMESPACE=openshift-devspaces
GOOGLE_CLOUD_PROJECT=my-project
CLOUD_ML_REGION=us-central1
```

`config.env` is gitignored — your settings stay local.

## Building the Image

The image must be built for **linux/amd64** since Dev Spaces clusters run on x86_64. If you're building on an ARM Mac:

```bash
podman build --platform linux/amd64 -t $(grep IMAGE config.env | cut -d= -f2) .
```

Or with the Makefile (add `--platform linux/amd64` to `BUILDFLAGS`):

```bash
make build
make push
```

## Deploying a Workspace

There are two deployment paths depending on your cluster access.

### Option A: Cluster-wide registration (requires admin)

If you have admin access to the `openshift-devspaces` namespace, register the editor so it appears in the dashboard editor picker for all users:

```bash
make register
```

Users can then select **T3 Code + Claude** when creating a workspace. To remove it later: `make unregister`.

### Option B: Per-user deployment (no admin required)

On shared clusters like the Developer Sandbox, create the workspace directly with `oc`. This uses a `DevWorkspaceTemplate` + `DevWorkspace` pair in your own namespace.

**1. Create the editor template:**

```bash
cat <<'EOF' | oc apply -n <your-namespace> -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspaceTemplate
metadata:
  name: t3-code-editor
spec:
  components:
    - name: t3-code-injector
      container:
        image: <your-image>
        command:
          - /entrypoint-init-container.sh
        volumeMounts:
          - name: t3code
            path: /t3code
        memoryLimit: 256Mi
        memoryRequest: 32Mi
        cpuLimit: 500m
        cpuRequest: 30m
    - name: t3-code-runtime
      container:
        image: quay.io/devfile/universal-developer-image:latest
        env:
          - name: CLAUDE_CODE_USE_VERTEX
            value: "1"
          - name: GOOGLE_CLOUD_PROJECT
            value: "<your-gcp-project>"
          - name: CLOUD_ML_REGION
            value: "<your-region>"
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
        controller.devfile.io/container-contribution: true
    - name: t3code
      volume: {}
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
EOF
```

**2. Create the workspace:**

```bash
cat <<'EOF' | oc apply -n <your-namespace> -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: t3-code-workspace
  labels:
    che.eclipse.org/devworkspace: "true"
spec:
  started: true
  routingClass: che
  contributions:
    - name: editor
      kubernetes:
        name: t3-code-editor
  template:
    projects:
      - name: my-project
        git:
          remotes:
            origin: https://github.com/your-org/your-repo.git
EOF
```

Replace `<your-namespace>`, `<your-image>`, `<your-gcp-project>`, `<your-region>`, and the git repo URL with your values.

## Accessing T3 Code

### Known issue: subpath routing

The default Dev Spaces workspace URL serves T3 Code under a subpath (e.g. `/username/workspace-name/3773/`). T3 Code's web assets use absolute paths (`/assets/...`), which break under subpath routing.

**Workaround:** Create a direct Route to bypass the Che gateway:

```bash
# Get the workspace ID
WS_ID=$(oc get devworkspace t3-code-workspace -n <your-namespace> -o jsonpath='{.status.devworkspaceId}')

# Create a direct service and route
cat <<EOF | oc apply -n <your-namespace> -f -
apiVersion: v1
kind: Service
metadata:
  name: t3-code-direct
spec:
  selector:
    controller.devfile.io/devworkspace_id: ${WS_ID}
  ports:
    - port: 3773
      targetPort: 3773
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: t3-code-direct
spec:
  to:
    kind: Service
    name: t3-code-direct
  port:
    targetPort: 3773
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

# Get your direct URL
oc get route t3-code-direct -n <your-namespace> -o jsonpath='https://{.spec.host}/'
```

This gives T3 Code its own hostname where asset paths resolve correctly.

> **Note:** This direct route bypasses Che cookie authentication. The T3 Code pairing token provides access control instead.

### Pairing token

T3 Code requires a one-time pairing token on first connect. Get it from the entrypoint logs:

```bash
POD=$(oc get pods -n <your-namespace> -l controller.devfile.io/devworkspace_name=t3-code-workspace --no-headers | grep -v cleanup | awk '{print $1}')
oc exec $POD -c t3-code-runtime -n <your-namespace> -- grep 'Token:' /t3code/entrypoint-logs.txt
```

Enter the token in the browser when prompted, or navigate directly to the pairing URL:

```
https://<your-route-host>/pair#token=<TOKEN>
```

## Authentication

The editor relies on enterprise-managed authentication. No API keys are stored in the workspace.

```
Developer → OpenShift Login → Workload Identity → Vertex AI → Claude
```

The only required env var is `CLAUDE_CODE_USE_VERTEX=true` (set in the devfile).

## Cleanup

```bash
# Delete the workspace
oc delete devworkspace t3-code-workspace -n <your-namespace>

# Delete the direct route and service (if created)
oc delete route t3-code-direct -n <your-namespace>
oc delete service t3-code-direct -n <your-namespace>

# Delete the editor template
oc delete devworkspacetemplate t3-code-editor -n <your-namespace>

# Unregister cluster-wide editor (admin only)
make unregister
```

## Files

| File | Purpose |
|------|---------|
| `config.env.example` | Template for local `config.env` (image, namespace, GCP project, region) |
| `Dockerfile` | Editor container image (UBI9 + Node.js 22 + T3 Code + Claude Code + gcloud) |
| `entrypoint.sh` | Runtime startup — launches `t3 serve --mode web` |
| `entrypoint-init-container.sh` | Init container — copies binaries into shared volume |
| `t3-code-editor-devfile.yaml` | Che editor definition template (rendered via `envsubst` at registration) |
| `Makefile` | Build, push, and registration targets |
| `devspace-t3code-plan.md` | Full architecture plan |

## Known Limitations

- **Subpath routing** — T3 Code assets use absolute paths, requiring a direct Route workaround (see above).
- **Architecture** — The image must be built for `linux/amd64`. Building on ARM requires `--platform linux/amd64` (emulated, slower).
- **gcloud CLI** — Installed via tarball extraction only (no `install.sh`) because UBI9 ships Python 3.9 which the latest gcloud installer requires 3.10+. The `gcloud` binary works fine without the installer.
- **T3 Code version** — T3 Code is at v0.0.x. Expect breaking changes. Pin versions in the Dockerfile and test upgrades before rolling out.
