#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
BOB_IMAGE="${BOB_IMAGE:?Set BOB_IMAGE in config.env}"
BOB_BACKEND="${BOB_BACKEND:-bob}"
case "$BOB_BACKEND" in
  bob|opencode) ;;
  *) echo "BOB_BACKEND must be bob or opencode" >&2; exit 1 ;;
esac
render_devfile "$REPO_ROOT/bob/devfile.yaml" --check

build_and_push_image "$BOB_IMAGE" "$REPO_ROOT/bob" "$BOB_BACKEND"
create_editor_template "$REPO_ROOT/bob/devfile.yaml" bob-editor
create_workspace bob-workspace bob-editor
wait_for_workspace bob-workspace 300s
WS_ID=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.controller\.devfile\.io/devworkspace_id}')
create_direct_route bob-direct 8000 controller.devfile.io/devworkspace_id "$WS_ID" 6m

echo "Waiting for Bob UI..."
for ((attempt=0; attempt<30; attempt++)); do
  if oc exec "$POD" -c bob-runtime -n "$NAMESPACE" -- node -e \
    'fetch("http://127.0.0.1:8000/healthz").then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
if [ "$attempt" -eq 30 ]; then
  echo "Bob UI did not become healthy. Inspect pod $POD." >&2
  exit 1
fi
ROUTE_HOST=$(oc get route bob-direct -n "$NAMESPACE" -o jsonpath='{.spec.host}')
UI_TOKEN=$(oc exec "$POD" -c bob-runtime -n "$NAMESPACE" -- cat /projects/.devspaces-bob/ui-token)
printf '\nBob UI: https://%s/\nToken:  %s\n' "$ROUTE_HOST" "$UI_TOKEN"
echo "Repository: /projects/repo"
echo "Backend: $BOB_BACKEND. See bob/README.md for configuration."
