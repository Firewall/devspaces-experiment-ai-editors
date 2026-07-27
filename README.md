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

`config.env` is gitignored — your settings stay local. Set `NAMESPACE` to your Dev Spaces user namespace (e.g. `rh-ee-yourname-dev`).

## Quick Start (no admin required)

The `deploy.sh` script handles everything — build, push, create workspace, create direct route:

```bash
cp config.env.example config.env
vi config.env
./deploy.sh
```

It will print the T3 Code URL and pairing token when done.

To tear down:

```bash
./teardown.sh
```

## What deploy.sh Does

1. Builds the container image for `linux/amd64` and pushes to your registry
2. Creates a `DevWorkspaceTemplate` (the editor definition) in your namespace
3. Creates a `DevWorkspace` that references the editor template
4. Waits for the workspace pod to be ready
5. Creates a direct OpenShift Route to T3 Code (bypasses the Che gateway — see "Known Issues" below)
6. Prints the URL and pairing token

## Pairing Token

T3 Code requires a one-time pairing token on first connect. The deploy script prints it automatically.

The token is persisted to the `/projects` volume (survives workspace restarts). To retrieve it later:

```bash
POD=$(oc get pods -n <your-namespace> -l controller.devfile.io/devworkspace_name=t3-code-workspace --no-headers | grep -v cleanup | awk '{print $1}')
oc exec $POD -c t3-code-runtime -n <your-namespace> -- cat /projects/.devspaces-t3code/pairing-token.txt
```

## Authenticating Claude (Vertex AI)

After the workspace starts, open a shell into the pod and authenticate:

```bash
POD=$(oc get pods -n <your-namespace> -l controller.devfile.io/devworkspace_name=t3-code-workspace --no-headers | grep -v cleanup | awk '{print $1}')
oc exec -it $POD -c t3-code-runtime -n <your-namespace> -- bash
export PATH=/t3code/npm-global/bin:/t3code/google-cloud-sdk/bin:$PATH
gcloud auth application-default login --no-launch-browser
```

Credentials are persisted to the `/projects` volume — you only need to do this once per workspace lifetime.

## Cluster-wide Registration (requires admin)

If you have admin access to the `openshift-devspaces` namespace, you can register the editor so it appears in the dashboard editor picker for all users:

```bash
make register
```

To remove: `make unregister`.

## Known Issues

- **Subpath routing** — The Che gateway serves T3 Code under a subpath (e.g. `/username/workspace/3773/`). T3 Code's assets use absolute paths (`/assets/...`) which break under subpath routing. The deploy script works around this by creating a direct Route with its own hostname. Upstream issue: [#2310](https://github.com/pingdotgg/t3code/issues/2310).
- **Dashboard "Open" button** — Shows "workspace has not received an IDE URL" because the endpoint doesn't set `type: main` (which would trigger a health-check timeout cycle). Use the direct Route URL instead.
- **ECONNRESET crashes** — The Che gateway probes the T3 Code port, causing unhandled `ECONNRESET` errors that crash the Node.js process. The entrypoint includes a restart loop that recovers in 2 seconds.
- **Architecture** — The image must be built for `linux/amd64`. Building on ARM requires `--platform linux/amd64` (emulated, slower).
- **gcloud CLI** — Installed via tarball (no `install.sh`) because UBI9 ships Python 3.9 and the latest gcloud installer requires 3.10+.
- **T3 Code version** — T3 Code is at v0.0.x. Expect breaking changes.

## Files

| File | Purpose |
|------|---------|
| `deploy.sh` | One-command deploy: build, push, create workspace, create route |
| `teardown.sh` | Remove all workspace resources |
| `config.env.example` | Template for local `config.env` |
| `Dockerfile` | Editor container image (UBI9 + Node.js 22 + T3 Code + Claude Code + gcloud) |
| `entrypoint.sh` | Runtime startup with auto-restart and persistent pairing token |
| `entrypoint-init-container.sh` | Init container — copies binaries into shared volume |
| `t3-code-editor-devfile.yaml` | Che editor definition template (for cluster-wide registration via `make register`) |
| `Makefile` | Build, push, and cluster-wide registration targets |
| `devspace-t3code-plan.md` | Full architecture plan |
