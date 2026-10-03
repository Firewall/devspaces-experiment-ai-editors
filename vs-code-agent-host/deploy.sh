#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
AGENT_HOST_IMAGE="${AGENT_HOST_IMAGE:?Set AGENT_HOST_IMAGE in config.env}"
render_devfile "$REPO_ROOT/vs-code-agent-host/devfile.yaml" --check

echo "=== Deploying VS Code Agent Host to namespace: $NAMESPACE ==="

# Step 1: Build and push image
build_and_push_image "$AGENT_HOST_IMAGE" "$REPO_ROOT/vs-code-agent-host"

# Step 2: Create DevWorkspaceTemplate
create_editor_template "$REPO_ROOT/vs-code-agent-host/devfile.yaml" "vs-code-agent-host-editor"

# Step 3: Create DevWorkspace
create_workspace "vs-code-agent-host-workspace" "vs-code-agent-host-editor"

# Step 4: Wait for pod
wait_for_workspace "vs-code-agent-host-workspace" 300s

# Step 5: Create direct route (bypasses Che gateway subpath routing)
WS_ID=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.controller\.devfile\.io/devworkspace_id}')
create_direct_route "agent-host-direct" 3773 controller.devfile.io/devworkspace_id "$WS_ID"

# Step 6: Wait for Agent Host to initialize
echo "Waiting for Agent Host to start..."
sleep 20

ROUTE_HOST=$(oc get route agent-host-direct -n "$NAMESPACE" -o jsonpath='{.spec.host}')
AGENT_HOST_TOKEN=$(oc exec "$POD" -c vs-code-agent-host -n "$NAMESPACE" -- \
  cat /projects/.devspaces-agent-host/connection-token 2>/dev/null || true)

echo ""
echo "=== VS Code Agent Host is ready ==="
echo ""
if [ -n "$AGENT_HOST_TOKEN" ]; then
  echo "Agent Host: https://${ROUTE_HOST}/?tkn=${AGENT_HOST_TOKEN}"
else
  echo "Agent Host token is not ready yet. Run:"
  echo "  oc exec $POD -c vs-code-agent-host -n $NAMESPACE -- cat /projects/.devspaces-agent-host/connection-token"
fi
echo ""
echo "Shell: oc exec -it $POD -c vs-code-agent-host -n $NAMESPACE -- bash"
echo ""
echo "Logs:  oc exec $POD -c vs-code-agent-host -n $NAMESPACE -- cat /tmp/agent-host-logs.txt"
echo ""
echo "Test:  make vscode-test"
