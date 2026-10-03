# AI editors for OpenShift Dev Spaces

Run T3 Code, OpenChamber, Orca, or VS Code Agent Host in OpenShift Dev Spaces workspaces. This repository contains container recipes, devfiles, and scripts that build an image and create a workspace in your user namespace.

This is an experiment. Direct OpenShift Routes work around Che gateway routing limitations, and upstream editor changes can break the integrations. It is a community project with no production support commitment.

| Integration | AI setup | Port | Authentication | Client |
| --- | --- | --- | --- | --- |
| [T3 Code](https://github.com/pingdotgg/t3code) | OpenCode with optional KServe model discovery | 3773 | Pairing token | Browser |
| [OpenChamber](https://github.com/openchamber/openchamber) | OpenCode providers, including KServe | 3000 | UI password | Browser |
| [Orca](https://github.com/stablyai/orca) | OpenCode with KServe model discovery | 6768 | Browser pairing URL | Browser |
| [VS Code Agent Host](https://code.visualstudio.com/) | Discovered KServe models and OpenCode | 3773 | Connection token | Compatible VS Code client |

VS Code Agent Host exposes an agent service. Its URL is a service endpoint for a compatible client, rather than a browser IDE.

## Requirements

- An OpenShift cluster with Dev Spaces installed.
- Bash and `podman` on your machine. The deploy scripts use Podman.
- Python 3 and the dependency in `requirements.txt` for devfile rendering.
- The `oc` CLI, logged in to the cluster.
- Permission to create DevWorkspaces, DevWorkspaceTemplates, Services, and Routes in your Dev Spaces user namespace.
- A registry you can push to and that workspace pods can pull from. A public image is convenient on shared clusters where you cannot configure pull credentials. Check [upstream terms](#license) before publishing images, particularly the VS Code integration.

Cluster-wide editor registration additionally needs admin permissions. Google Vertex AI is optional and requires a Google Cloud project with access to your chosen models.

Install the local renderer dependency in a virtual environment and activate it before running deployment, registration, or tests:

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
```

## Configure

```bash
cp config.env.example config.env
${EDITOR:-vi} config.env
```

Set `NAMESPACE` to your Dev Spaces user namespace and replace `my-org` in the image names for the editors you want to deploy:

```env
NAMESPACE=rh-ee-yourname-dev
T3_IMAGE=quay.io/my-org/devspaces-t3-code-editor:latest
OPENCHAMBER_IMAGE=quay.io/my-org/devspaces-openchamber-editor:latest
ORCA_IMAGE=quay.io/my-org/devspaces-orca-editor:latest
AGENT_HOST_IMAGE=quay.io/my-org/devspaces-vs-code-agent-host:latest
```

Run `oc project -q` to check your current namespace. The scripts require an explicit `NAMESPACE`; the namespace hosting the Dev Spaces operator is usually different from your user namespace.

`config.env` is a local, gitignored Bash file. Leave `GOOGLE_CLOUD_PROJECT` empty unless you use Vertex AI. OpenChamber generates a UI password if `OPENCHAMBER_UI_PASSWORD` is unset.

## Deploy

Run the script for your chosen editor from the repository root:

```bash
./t3-code/deploy.sh
# or
./openchamber/deploy.sh
# or
./orca/deploy.sh
# or
./vs-code-agent-host/deploy.sh
```

Each script builds and pushes a `linux/amd64` image, creates an editor template and workspace, waits for the pod, and creates a direct HTTPS Route. It then prints the connection URL and credential. Keep that output private.

Orca creates its Route before starting the workspace so its pairing URL advertises the external WebSocket address. The other integrations create the Route after the pod starts.

The workspace initially has no source repository. Add or clone your code under `/projects` after connecting. Each integration uses fixed workspace and resource names, so rerunning its script updates the same resources in the configured namespace.

For VS Code Agent Host, check a running deployment with:

```bash
./vs-code-agent-host/test.sh
```

The test checks the pod, CLI, model files, token, bubblewrap, service, and Route. Bubblewrap depends on the cluster allowing user namespaces; a failed check means you should not assume sandboxing works.

## Credentials and access

Direct Routes bypass the Che gateway. Access depends on the editor's own password, pairing, or connection token. The Routes terminate TLS and redirect HTTP to HTTPS.

Credentials persist under `/projects/.devspaces-*`. Entrypoints restrict the state directory to the workspace user and credential files to mode `600`. Our startup scripts do not print T3 pairing tokens or OpenChamber passwords into runtime logs. The deploy scripts deliberately print credentials so you can connect.

To retrieve a credential later, find the workspace pod and read the file for your integration:

| Integration | Workspace | Container | Credential file |
| --- | --- | --- | --- |
| T3 Code | `t3-code-workspace` | `t3-code-runtime` | `/projects/.devspaces-t3code/pairing-token.txt` |
| OpenChamber | `openchamber-workspace` | `openchamber-runtime` | `/projects/.devspaces-openchamber/ui-password.txt` |
| Orca | `orca-workspace` | `orca-runtime` | `/projects/.devspaces-orca/ready.jsonl` |
| VS Code Agent Host | `vs-code-agent-host-workspace` | `vs-code-agent-host` | `/projects/.devspaces-agent-host/connection-token` |

For example, to retrieve the T3 Code token:

```bash
source ./config.env
POD=$(oc get pods -n "$NAMESPACE" \
  -l controller.devfile.io/devworkspace_name=t3-code-workspace \
  --no-headers | awk '$3 != "Completed" && $1 !~ /cleanup/ {print $1; exit}')
oc exec "$POD" -c t3-code-runtime -n "$NAMESPACE" -- \
  cat /projects/.devspaces-t3code/pairing-token.txt
```

For Orca, use the full `pairing.webClientUrl` in its readiness JSON, including the fragment. Treat that URL as a credential. T3 Code creates a pairing token with a 30-day lifetime; an expired, unused token needs to be recreated.

Keep passwords, pairing URLs, logs, and generated model configuration out of issues and pull requests. VS Code's `chatLanguageModels.json` contains a service account token and is written with mode `600`.

## AI providers

### KServe model discovery

The integrations look for KServe InferenceServices in `sandbox-shared-models`. The workspace service account needs permission to list them and authenticate to their model endpoints. Discovery generates `/projects/opencode.json`; VS Code Agent Host also generates `/projects/chatLanguageModels.json`.

For Orca, set `REDHAT_AI_NAMESPACE` in `config.env` before running `./orca/deploy.sh`. For the other integrations, add that environment variable to the runtime component in the relevant `deploy.sh` and `devfile.yaml`. The namespace default targets a shared sandbox setup and may not exist on your cluster.

Discovery skips missing or unreachable services. If your cluster has no shared models, configure an OpenCode provider yourself. T3 Code, OpenChamber, and VS Code Agent Host generate a config that disables OpenCode's own tools for use as an editor backend. Orca keeps OpenCode's default tools and permissions.

In Orca, open a terminal in your repository, run `opencode`, and select a Red Hat AI model with `/models`. Orca sets `OPENCODE_CONFIG` to the generated `/projects/opencode.json`, so discovery also works inside cloned repositories and worktrees. OpenCode merges that config with your user and project settings.

### Other providers

OpenCode supports external providers. Open a workspace terminal or use `oc exec -it` with the container listed above, then configure your provider using [OpenCode's provider documentation](https://opencode.ai/docs/providers/).

For Google Vertex AI, set the project and region required by your provider configuration, then authenticate from the workspace:

```bash
gcloud auth application-default login --no-launch-browser
```

OpenChamber and Orca persist OpenCode and Google Cloud state on `/projects`. T3 Code persists its editor state and Google Cloud state. VS Code Agent Host persists its server state and Google Cloud state. Other coding agent CLIs can be installed and authenticated in the workspace terminal.

## Remove a deployment

Use the matching teardown script:

```bash
./t3-code/teardown.sh
# or
./openchamber/teardown.sh
# or
./orca/teardown.sh
# or
./vs-code-agent-host/teardown.sh
```

Teardown removes the integration's workspace, editor template, direct Service, and Route in `NAMESPACE`. Storage retention follows your cluster's DevWorkspace policy. Back up anything you need from `/projects` first.

## Cluster-wide registration

The deploy scripts create templates in your namespace. To add editor definitions to the dashboard picker for everyone, set `NAMESPACE` to the Dev Spaces installation namespace and use the admin registration targets:

```bash
make t3-register
make chamber-register
make orca-register
make vscode-register
```

Remove definitions with the matching `*-unregister` target. For manual Orca registration, also set `ORCA_PAIRING_ADDRESS` to a reachable `wss://` endpoint. Its deploy script calculates that address automatically. Restore your user namespace in `config.env` before deploying or tearing down a workspace.

## Versions and limitations

The Containerfiles pin T3 Code, OpenChamber, OpenCode, and Orca to explicit versions. T3 Code currently uses a dated nightly release. Update the version declarations when testing a newer release. Base images, Google Cloud SDK downloads, the OpenShift CLI, and the VS Code stable CLI still follow moving releases, so builds are not fully reproducible.

Images target `linux/amd64`. On ARM machines, most stages need emulation. Orca builds on the host architecture and packages an amd64 runtime to avoid esbuild failures under emulation. Orca v1.4.219 needs [web-client.patch](orca/web-client.patch) to serve its web client and initialize terminal creation.

T3 Code and OpenChamber assets use absolute paths that break under Che gateway subpaths. The direct Routes work around this, but the dashboard Open button may still lack an IDE URL. Use the URL printed by the deploy script. See [T3 Code's routing issue](https://github.com/pingdotgg/t3code/issues/2310).

Che gateway probes can trigger Node.js `ECONNRESET` exits. The T3 Code and OpenChamber entrypoints restart the server after two seconds. This recovers the process but does not fix the upstream error.

OpenChamber includes a Red Hat Dark theme. Load it through Settings, Theme, Reload themes, then select Red Hat Dark.

## Repository layout

Each editor directory contains its `Containerfile`, `devfile.yaml`, `deploy.sh`, `teardown.sh`, and startup scripts. T3 Code, OpenChamber, and Orca inject their runtime into a universal developer image. VS Code Agent Host runs its own image directly.

Each `devfile.yaml` defines the editor components, commands, and events. Deployment and admin registration use the same renderer, so changes to those definitions belong in the devfile. The renderer substitutes configuration values and preserves runtime variables such as `$PATH`.

`shared/` contains deployment helpers, the devfile renderer, runtime setup, and KServe discovery. `config.env.example` documents local configuration. The `Makefile` provides build, push, and admin registration targets.

For local changes, check Bash syntax and run ShellCheck before testing a deployment. Keep credentials and rendered devfiles out of commits.

Run the local discovery and editor-script checks with `python3 -m unittest discover -s tests`. They mock cluster and build commands and require Bash and Node.js.

## License

The integration code is licensed under [MIT](LICENSE). [T3 Code](https://github.com/pingdotgg/t3code), [OpenChamber](https://github.com/openchamber/openchamber), [Orca](https://github.com/stablyai/orca), [OpenCode](https://github.com/anomalyco/opencode), and their dependencies keep their own licenses. Preserve upstream license files and notices when redistributing images.

The Orca integration applies a small patch and includes its [upstream license](https://github.com/stablyai/orca/blob/v1.4.219/LICENSE) in the runtime image. VS Code binaries have separate [Microsoft product](https://code.visualstudio.com/license) and [server terms](https://code.visualstudio.com/license/server); review those before distributing an image or offering a hosted service.
