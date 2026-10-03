#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
T3_IMAGE="${T3_IMAGE:?Set T3_IMAGE in config.env}"
render_devfile "$REPO_ROOT/t3-code/devfile.yaml" --check

echo "=== Deploying T3 Code to namespace: $NAMESPACE ==="

# Step 1: Build and push image
build_and_push_image "$T3_IMAGE" "$REPO_ROOT/t3-code"

# Step 2: Create DevWorkspaceTemplate
create_editor_template "$REPO_ROOT/t3-code/devfile.yaml" "t3-code-editor"

# Step 3: Create DevWorkspace
create_workspace "t3-code-workspace" "t3-code-editor"

# Step 4: Wait for pod
wait_for_workspace "t3-code-workspace" 180s

# Step 5: Create direct route (bypasses Che gateway subpath routing)
WS_ID=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.controller\.devfile\.io/devworkspace_id}')
create_direct_route "t3-code-direct" 3773 controller.devfile.io/devworkspace_id "$WS_ID"

# Step 6: Get pairing token
echo "Waiting for T3 Code to start..."
sleep 15
PAIRING_TOKEN=$(oc exec "$POD" -c t3-code-runtime -n "$NAMESPACE" -- cat /projects/.devspaces-t3code/pairing-token.txt 2>/dev/null || true)
if [ -z "$PAIRING_TOKEN" ]; then
  sleep 10
  PAIRING_TOKEN=$(oc exec "$POD" -c t3-code-runtime -n "$NAMESPACE" -- cat /projects/.devspaces-t3code/pairing-token.txt 2>/dev/null || true)
fi

ROUTE_HOST=$(oc get route t3-code-direct -n "$NAMESPACE" -o jsonpath='{.spec.host}')

echo ""
echo "=== T3 Code is ready ==="
echo ""
echo "URL:   https://${ROUTE_HOST}/"
if [ -n "$PAIRING_TOKEN" ]; then
  echo "Pair:  https://${ROUTE_HOST}/pair#token=${PAIRING_TOKEN}"
else
  echo "Pair:  Token not ready yet. Run:"
  echo "       oc exec \$(oc get pods -n $NAMESPACE -l controller.devfile.io/devworkspace_name=t3-code-workspace --no-headers | grep -v cleanup | awk '{print \$1}') -c t3-code-runtime -n $NAMESPACE -- cat /projects/.devspaces-t3code/pairing-token.txt"
fi
echo ""
echo "Shell: oc exec -it $POD -c t3-code-runtime -n $NAMESPACE -- bash"
echo ""
echo "KServe models are discovered automatically when the workspace can access them."
echo "For optional Vertex AI authentication:"
echo "  oc exec -it $POD -c t3-code-runtime -n $NAMESPACE -- bash"
echo "  export PATH=/t3code/npm-global/bin:/t3code/google-cloud-sdk/bin:\$PATH"
echo "  gcloud auth application-default login --no-launch-browser"
