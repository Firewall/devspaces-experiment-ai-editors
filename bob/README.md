# Headless Bob and OpenCode proof of concept

This integration runs the [Headless Bob reference implementation](https://github.com/ibm-self-serve-assets/building-blocks/tree/6c4a26ff8d315d0ec9fdebffb03e27f0bf9aa879/ai/engineering/headless-bob) in a Dev Spaces workspace. It provides browser chat, streaming output, conversation history, and file browsing. The console can use IBM Bob Shell or OpenCode for agent work. It has no integrated text editor or terminal.

The container pins upstream commit `6c4a26ff8d315d0ec9fdebffb03e27f0bf9aa879`. The wrapper keeps its Apache 2.0 license. The `opencode` image target uses the Dev Spaces OpenCode injector and excludes Bob Shell. The `bob` image target includes Bob Shell `2.0.4`, verifies its package SHA-256, and retains IBM's separate terms. Keep images containing Bob Shell private unless your entitlement permits redistribution.

`dependencies.patch` updates compatible versions in the wrapper's lockfile to address the dependency advisories found during this PoC. Image builds run ten checks covering shared repository storage, OpenCode session continuation, tool approval, credential isolation, and free model configuration.

## Deploy with a free OpenCode model

Set these values in `config.env`, using your own registry repository:

```bash
BOB_IMAGE=quay.io/YOUR_ORG/devspaces-bob-editor:opencode-free-poc
BOB_BACKEND=opencode
BOB_OPENCODE_MODEL=opencode/glm-5.3-flash-free
```

Then run:

```bash
./bob/deploy.sh
```

The console uses OpenCode through ACP. Both its main model and background model use the selected free model. The generated configuration enables only the OpenCode provider and whitelists that model. The launcher excludes paid provider API keys and the browser token from the agent environment. No Bob API key is needed.

The model name must use the `opencode/` provider and end in `-free`; paid model names fail configuration validation. Free model availability can change. Check the [OpenCode model list](https://opencode.ai/v2/docs/console/models/) before choosing another free model.

## Local Bob preview

The following local preview uses the IBM Bob backend:

```bash
podman build --platform linux/amd64 -f bob/Containerfile -t localhost/devspaces-bob-editor:poc .
podman run -d --name devspaces-bob-poc --platform linux/amd64 \
  --user 100123:0 -p 127.0.0.1:8000:8000 \
  -v devspaces-bob-poc-data:/projects localhost/devspaces-bob-editor:poc
podman exec devspaces-bob-poc cat /projects/.devspaces-bob/ui-token
```

Open `http://localhost:8000` and enter the printed token. Keep it private. The named volume retains state when the container is removed. To enable inference locally, recreate the container with a read-only credential directory mount as described below. Remove the preview with `podman rm -f devspaces-bob-poc`; the named volume remains.

## Deploy with IBM Bob Shell

For IBM Bob Shell, set `BOB_BACKEND=bob` and `BOB_IMAGE` in `config.env`, then run:

```bash
./bob/deploy.sh
```

For a private image, configure a [Dev Spaces image pull Secret](https://eclipse.dev/che/docs/stable/end-user-guide/creating-image-pull-secrets/) in your user namespace before deployment. Include only the credentials for the registry that hosts this image. The deployment does not change registry visibility.

The script builds and pushes the image, registers a namespaced editor template, creates `bob-workspace`, and exposes port 8000 through the `bob-direct` HTTPS Route. It prints a private UI token. Enter that token on the browser connection screen.

The workspace selects the Dev Spaces OpenCode tool through a pinned injector and the `install-opencode` startup command. With `BOB_BACKEND=opencode`, this executable handles console requests. With `BOB_BACKEND=bob`, the console uses IBM Bob Shell and OpenCode remains available as a separate CLI.

`/healthz` checks the service. Authenticated `/readyz` checks the selected executable and, for Bob, the presence of a Bob API key. Readiness does not make an inference request. Use the live check below to verify model access.

## Configure live Bob access

Install and launch [Bob Shell](https://bob.ibm.com/docs/shell/getting-started/install-and-setup) locally. Review and accept its license through Bob Shell. This integration imports only the saved `licenseConsent` flag, leaving personal Bob settings and credentials on your machine.

Create an **Inference** API key in your Bob subscription and save it in a private local file. Restrict its permissions to your user. Pass the file path and your Bob settings path:

```bash
./bob/configure.sh /private/path/bob-api-key "$HOME/.bob/settings/settings.json"
```

The script creates `bob-credentials` in your configured namespace using file contents sent through stdin. It does not print the key. DevWorkspace mounts the Secret at `/etc/secret/bob-credentials`, scoped to `bob-workspace`, on its next start. Stop and start the workspace through the Dev Spaces dashboard after creating or updating credentials. Other workspaces do not need to restart.

For a local container, mount a directory containing `BOB_API_KEY` and `settings.json` at `/etc/secret/bob-credentials:ro`. Credentials stay out of the image and devfile. This PoC targets IBM's hosted Bob service. It does not configure a self-hosted Bob gateway or use the repo's KServe discovery.

## Work on a repository

All conversations operate on `/projects/repo`. To populate it, open a shell using the pod name printed during deployment or locate the pod in the dashboard:

```bash
oc exec -it POD_NAME -c bob-runtime -n YOUR_NAMESPACE -- bash
git clone https://github.com/YOUR_ORG/YOUR_REPO.git /projects/repo
```

An empty directory already exists at that path. Git can clone into it while it remains empty. You can also copy an existing checkout there. Start a browser conversation and ask the agent to inspect the repository. Changes go directly into that checkout. The file browser becomes available after the conversation has a session and the run has finished. Upstream hides dotfiles and does not follow symlinks in file downloads.

`shared-repository.patch` adds the fixed repository path to upstream storage. It retains canonical path validation and requires one service owner and `MAX_CONCURRENT=1`. All conversations share files; only their chat history is separate. The upstream API normally gives each session its own directory. This modification is intended for one user per DevWorkspace.

State persists under `/projects/.devspaces-bob`:

- `service/` contains conversation metadata and SQLite databases.
- `home/.bob/` contains Bob's history and saved license consent when using Bob.
- OpenCode config, session data, state, and cache use XDG directories under `home/`.
- `ui-token` contains the browser credential, with mode `600`.

The selected agent can run commands with the workspace user's permissions. The wrapper automatically approves individual tool requests. Use a dedicated workspace for code you trust. The Bob backend disables MCP and subagents through its launch flags. The ACP runtime does not enforce the wrapper's legacy cost or turn limits; the OpenCode backend pins requests to its configured free model.

## Verify and remove

```bash
./bob/test.sh
./bob/test.sh --live
```

The default check verifies the UI, authentication, selected agent version, shared repository, and storage permissions without making an inference request. For OpenCode it also checks readiness and the free model selection. `--live` asks the agent to write a uniquely named marker file, restarts the workspace, then resumes the same conversation to check that the marker and conversation survive. It briefly stops this workspace. It uses the configured free model with OpenCode, or Bob credits with the IBM backend. The marker is removed after verification.

```bash
./bob/teardown.sh
```

Teardown retains credential and image pull Secrets. Remove `bob-credentials` explicitly with `oc delete secret bob-credentials -n YOUR_NAMESPACE` when no longer needed. Remove an image pull Secret only if no other workspace uses it. Storage retention follows DevWorkspace policy. Back up `/projects` first.
