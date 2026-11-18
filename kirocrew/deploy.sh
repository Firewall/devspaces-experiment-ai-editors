#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
KIROCREW_IMAGE="${KIROCREW_IMAGE:?Set KIROCREW_IMAGE in config.env}"
render_devfile "$REPO_ROOT/kirocrew/devfile.yaml" --check

echo "=== Deploying KiroCrew to namespace: $NAMESPACE ==="

# Step 1: Build and push
build_and_push_image "$KIROCREW_IMAGE" "$REPO_ROOT/kirocrew"

# Step 2: Create the direct route before startup so the gateway can allowlist
# the public origin. The dashboard rejects proxied requests from unknown hosts.
create_direct_route "kirocrew-direct" 5476 controller.devfile.io/devworkspace_name "kirocrew-workspace" "1h"

ROUTE_HOST=$(oc get route kirocrew-direct -n "$NAMESPACE" -o jsonpath='{.spec.host}')
KIROCREW_PUBLIC_ORIGIN="https://${ROUTE_HOST}"
export KIROCREW_PUBLIC_ORIGIN

# Step 3: DevWorkspaceTemplate
create_editor_template "$REPO_ROOT/kirocrew/devfile.yaml" "kirocrew-editor"

# Step 4: DevWorkspace
create_workspace "kirocrew-workspace" "kirocrew-editor"

# Step 5: Wait for the workspace pod
wait_for_workspace "kirocrew-workspace" 300s

# Step 6: Wait for the gateway and mint a sign-in link. The link must be opened
# within five minutes; the session it mints lasts up to 20 hours and refreshes
# for 30 idle days.
echo "Waiting for the KiroCrew gateway..."
READY=""
for _ in $(seq 1 60); do
  if oc exec "$POD" -c kirocrew-runtime -n "$NAMESPACE" -- \
      curl -fsS "http://127.0.0.1:5476/api/health" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 3
done

LOGIN_URL=""
if [ -n "$READY" ]; then
  LOGIN_URL=$(oc exec "$POD" -c kirocrew-runtime -n "$NAMESPACE" -- \
    kirocrew token --ttl 20h 2>/dev/null || true)
  LOGIN_URL=$(printf '%s\n' "$LOGIN_URL" | grep -oE 'https?://[^[:space:]]*token=[^[:space:]]*' | head -n 1 || true)
  if [ -n "$LOGIN_URL" ]; then
    LOGIN_URL=$(printf '%s\n' "$LOGIN_URL" | \
      sed -e "s#http://localhost:5476#https://${ROUTE_HOST}#" \
          -e "s#http://127.0.0.1:5476#https://${ROUTE_HOST}#")
  fi
fi

echo ""
echo "=== KiroCrew is ready ==="
echo ""
echo "URL:   https://${ROUTE_HOST}/"
if [ -n "$LOGIN_URL" ]; then
  echo "Login: ${LOGIN_URL}"
  echo ""
  echo "Open the login link within five minutes; it mints a session that lasts up to 20 hours."
else
  echo "Login: Not ready yet. Mint a link with:"
  echo "       oc exec $POD -c kirocrew-runtime -n $NAMESPACE -- kirocrew token --ttl 20h"
  echo "       then replace localhost:5476 with ${ROUTE_HOST}."
fi
echo ""
echo "Chat sessions run on kiro-cli and need a Kiro sign-in:"
echo "  oc exec -it $POD -c kirocrew-runtime -n $NAMESPACE -- kiro-cli login"
echo ""
echo "Shell: oc exec -it $POD -c kirocrew-runtime -n $NAMESPACE -- bash"
echo "Logs:  oc logs $POD -c kirocrew-runtime -n $NAMESPACE"
echo ""
echo "State is /projects/.devspaces-kirocrew/.kiro/crew. Agent config is"
echo "/projects/.devspaces-kirocrew/.kiro/crew/config.json."
