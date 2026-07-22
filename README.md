# T3 Code — Dev Spaces Editor

Packages [T3 Code](https://github.com/pingdotgg/t3code) as a native OpenShift Dev Spaces editor alongside Che Code.

See [devspace-t3code-plan.md](devspace-t3code-plan.md) for the full architecture and design rationale.

## Prerequisites

- `podman` (or `docker`)
- `oc` CLI authenticated to the Dev Spaces cluster
- A container registry you can push to
- Google Vertex AI project with Claude enabled

## Configuration

Edit `config.env` with your values:

```env
IMAGE=quay.io/my-org/devspaces-t3-code-editor:latest
NAMESPACE=openshift-devspaces
GOOGLE_CLOUD_PROJECT=my-project
CLOUD_ML_REGION=us-central1
```

All placeholders are in this single file. The Makefile and devfile both read from it.

## Quick Start

```bash
# 1. Edit config.env with your values
vi config.env

# 2. Build the editor image
make build

# 3. Push to your registry
make push

# 4. Register the editor in Dev Spaces
make register
```

## Creating a Workspace

After registration, the Dev Spaces dashboard shows **T3 Code + Claude** in the editor picker. Select it when creating a workspace — T3 Code starts automatically and opens in the browser.

## Authentication

The editor relies on enterprise-managed authentication. No API keys are stored in the workspace.

```
Developer → OpenShift Login → Workload Identity → Vertex AI → Claude
```

The only required env var is `CLAUDE_CODE_USE_VERTEX=true` (set in the devfile).

## Unregistering

```bash
make unregister
```

## Files

| File | Purpose |
|------|---------|
| `config.env` | All configurable values (image, namespace, GCP project, region) |
| `Dockerfile` | Editor container image (UBI9 + Node.js 22 + T3 Code + Claude Code + gcloud) |
| `entrypoint.sh` | Runtime startup — launches `t3 serve` |
| `entrypoint-init-container.sh` | Init container — copies binaries into shared volume |
| `t3-code-editor-devfile.yaml` | Che editor definition template (rendered via `envsubst` at registration) |
| `Makefile` | Build, push, and registration targets |
| `devspace-t3code-plan.md` | Full architecture plan |
