#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
OPENCLAW_IMAGE="${OPENCLAW_IMAGE:?Set OPENCLAW_IMAGE in config.env}"
render_devfile "$REPO_ROOT/openclaw/devfile.yaml" --check

echo "=== Deploying OpenClaw to namespace: $NAMESPACE ==="

# Step 1: Build and push
build_and_push_image "$OPENCLAW_IMAGE" "$REPO_ROOT/openclaw"

# Step 2: Create the direct route before startup so the gateway can allowlist
# its public origin (the devfile renders OPENCLAW_PUBLIC_ORIGIN from this host).
create_direct_route "openclaw-direct" 18789 controller.devfile.io/devworkspace_name "openclaw-workspace" "1h"

ROUTE_HOST=$(oc get route openclaw-direct -n "$NAMESPACE" -o jsonpath='{.spec.host}')
OPENCLAW_PUBLIC_ORIGIN="https://${ROUTE_HOST}"
export OPENCLAW_PUBLIC_ORIGIN

# Step 3: DevWorkspaceTemplate
create_editor_template "$REPO_ROOT/openclaw/devfile.yaml" "openclaw-editor"

# Step 4: DevWorkspace
create_workspace "openclaw-workspace" "openclaw-editor"

# Step 5: Wait for the workspace pod
wait_for_workspace "openclaw-workspace" 300s

# Step 6: Read the gateway token. The first start also seeds config and state.
echo "Waiting for OpenClaw to start..."
GATEWAY_TOKEN=""
for _ in $(seq 1 60); do
  GATEWAY_TOKEN=$(oc exec "$POD" -c openclaw-runtime -n "$NAMESPACE" -- \
    cat /projects/.devspaces-openclaw/gateway-token 2>/dev/null || true)
  [ -n "$GATEWAY_TOKEN" ] && break
  sleep 3
done

echo ""
echo "=== OpenClaw is ready ==="
echo ""
echo "URL:   https://${ROUTE_HOST}/"
if [ -n "$GATEWAY_TOKEN" ]; then
  echo "Token: ${GATEWAY_TOKEN}"
else
  echo "Token: Not ready yet. Check the startup logs, then run:"
  echo "       oc exec $POD -c openclaw-runtime -n $NAMESPACE -- cat /projects/.devspaces-openclaw/gateway-token"
fi
echo ""
echo "Open the URL, paste the token into the Control UI, and set your model in Settings."
echo ""
echo "Shell: oc exec -it $POD -c openclaw-runtime -n $NAMESPACE -- bash"
echo "Logs:  oc exec $POD -c openclaw-runtime -n $NAMESPACE -- cat /tmp/openclaw-logs.txt"
echo ""
echo "Config is /projects/.devspaces-openclaw/openclaw.json. Delete that file to reseed it."
echo "If the Control UI rejects the browser origin, set OPENCLAW_PUBLIC_ORIGIN in config.env"
echo "and rerun this script (admin registration needs it too)."
