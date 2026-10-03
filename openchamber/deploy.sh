#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
OPENCHAMBER_IMAGE="${OPENCHAMBER_IMAGE:?Set OPENCHAMBER_IMAGE in config.env}"
render_devfile "$REPO_ROOT/openchamber/devfile.yaml" --check

echo "=== Deploying OpenChamber to namespace: $NAMESPACE ==="

# Step 1: Build and push
build_and_push_image "$OPENCHAMBER_IMAGE" "$REPO_ROOT/openchamber"

# Step 2: DevWorkspaceTemplate
create_editor_template "$REPO_ROOT/openchamber/devfile.yaml" "openchamber-editor"

# Step 3: DevWorkspace
create_workspace "openchamber-workspace" "openchamber-editor"

# Step 4: Wait for pod
wait_for_workspace "openchamber-workspace" 180s

# Step 5: Direct route (bypasses Che gateway subpath routing — same issue as T3 Code)
WS_ID=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.controller\.devfile\.io/devworkspace_id}')
create_direct_route "openchamber-direct" 3000 controller.devfile.io/devworkspace_id "$WS_ID"

# Step 6: Get UI password
echo "Waiting for OpenChamber to start..."
sleep 15
UI_PASSWORD=$(oc exec "$POD" -c openchamber-runtime -n "$NAMESPACE" -- cat /projects/.devspaces-openchamber/ui-password.txt 2>/dev/null || true)
if [ -z "$UI_PASSWORD" ]; then
  sleep 10
  UI_PASSWORD=$(oc exec "$POD" -c openchamber-runtime -n "$NAMESPACE" -- cat /projects/.devspaces-openchamber/ui-password.txt 2>/dev/null || true)
fi

ROUTE_HOST=$(oc get route openchamber-direct -n "$NAMESPACE" -o jsonpath='{.spec.host}')

echo ""
echo "=== OpenChamber is ready ==="
echo ""
echo "URL:      https://${ROUTE_HOST}/"
if [ -n "$UI_PASSWORD" ]; then
  echo "Password: ${UI_PASSWORD}"
elif [ -n "$OPENCHAMBER_UI_PASSWORD" ]; then
  echo "Password: ${OPENCHAMBER_UI_PASSWORD}  (from config.env)"
else
  echo "Password: Not ready yet. Run:"
  echo "          oc exec \$(oc get pods -n $NAMESPACE -l controller.devfile.io/devworkspace_name=openchamber-workspace --no-headers | grep -v cleanup | awk '{print \$1}') -c openchamber-runtime -n $NAMESPACE -- cat /projects/.devspaces-openchamber/ui-password.txt"
fi
echo ""
echo "Shell:    oc exec -it $POD -c openchamber-runtime -n $NAMESPACE -- bash"
echo ""
echo "To configure your LLM provider, shell in and edit ~/.config/opencode/config.json"
echo "For Vertex AI, also run:"
echo "  export PATH=/openchamber/npm-global/bin:/openchamber/google-cloud-sdk/bin:\$PATH"
echo "  gcloud auth application-default login --no-launch-browser"
