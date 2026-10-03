#!/bin/bash
# End-to-end validation for the VS Code Agent Host workspace.
# Run after deploy.sh completes.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -f "$REPO_ROOT/config.env" ]; then
  echo "config.env not found. Set NAMESPACE in config.env before testing."
  exit 1
fi
source "$REPO_ROOT/config.env"
NAMESPACE="${NAMESPACE:?Set NAMESPACE to your Dev Spaces user namespace in config.env}"
WS_NAME="vs-code-agent-host-workspace"
CONTAINER="vs-code-agent-host"

PASS=0
FAIL=0
WARN=0

check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  [PASS] $label"
    ((PASS++))
  else
    echo "  [FAIL] $label"
    ((FAIL++))
  fi
}

warn() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  [PASS] $label"
    ((PASS++))
  else
    echo "  [WARN] $label"
    ((WARN++))
  fi
}

exec_pod() {
  oc exec "$POD" -c "$CONTAINER" -n "$NAMESPACE" -- "$@"
}

echo "=== VS Code Agent Host integration test ==="
echo ""

# --- Pod ---
echo "Pod:"
POD=$(oc get pods -n "$NAMESPACE" -l "controller.devfile.io/devworkspace_name=$WS_NAME" --no-headers 2>/dev/null | grep -v cleanup | grep -v Completed | awk '{print $1}')
if [ -z "$POD" ]; then
  echo "  [FAIL] No pod found for workspace $WS_NAME"
  echo ""
  echo "Run ./vs-code-agent-host/deploy.sh first."
  exit 1
fi
echo "  [PASS] Pod: $POD"
((PASS++))

check "Pod is Ready" oc wait --for=condition=Ready "pod/$POD" -n "$NAMESPACE" --timeout=10s

# --- CLI binary ---
echo ""
echo "VS Code CLI:"
CLI_VERSION=$(exec_pod code --version 2>&1)
if [ $? -eq 0 ]; then
  echo "  [PASS] CLI binary works: $(echo "$CLI_VERSION" | head -1)"
  ((PASS++))
else
  echo "  [FAIL] CLI binary failed: $CLI_VERSION"
  ((FAIL++))
  exec_pod file /usr/local/bin/code 2>&1 | sed 's/^/    /'
  exec_pod ldd /usr/local/bin/code 2>&1 | sed 's/^/    /'
fi

# --- Model discovery ---
echo ""
echo "Model discovery:"
check "opencode.json exists" exec_pod test -f /projects/opencode.json
check "chatLanguageModels.json exists" exec_pod test -f /projects/chatLanguageModels.json

MODEL_COUNT=$(exec_pod cat /projects/chatLanguageModels.json 2>/dev/null | grep -c '"id"' 2>/dev/null || true)
MODEL_COUNT=${MODEL_COUNT:-0}
echo "  [INFO] Discovered $MODEL_COUNT model(s)"

# --- Connection token ---
echo ""
echo "Connection token:"
AGENT_HOST_TOKEN=$(exec_pod cat /projects/.devspaces-agent-host/connection-token 2>/dev/null)
if [ -n "$AGENT_HOST_TOKEN" ]; then
  echo "  [PASS] Connection token exists"
  ((PASS++))
else
  echo "  [FAIL] Connection token not found"
  ((FAIL++))
fi

# --- Bubblewrap sandbox ---
echo ""
echo "Sandbox:"
BWRAP_OUT=$(exec_pod bwrap --unshare-net --dev-bind / / echo "ok" 2>&1)
if echo "$BWRAP_OUT" | grep -q "ok"; then
  echo "  [PASS] bubblewrap can create user namespaces"
  ((PASS++))
else
  echo "  [WARN] bubblewrap failed: $(echo "$BWRAP_OUT" | head -1)"
  ((WARN++))
  SELINUX=$(exec_pod id -Z 2>/dev/null || echo "unknown")
  echo "  [INFO] SELinux context: $SELINUX"
fi

check "socat available" exec_pod which socat

# --- Agent Host process ---
echo ""
echo "Agent Host:"
check "Port 3773 is listening" exec_pod ss -tlnp '( sport = :3773 )'

CURL_STATUS=$(exec_pod curl -so /dev/null -w '%{http_code}' \
  "http://localhost:3773/?tkn=${AGENT_HOST_TOKEN}" 2>/dev/null || echo "000")
if [ "$CURL_STATUS" != "000" ]; then
  echo "  [PASS] Agent Host responding (HTTP $CURL_STATUS)"
  ((PASS++))
else
  echo "  [FAIL] Agent Host not responding on localhost:3773"
  ((FAIL++))
fi

# --- Route ---
echo ""
echo "Route:"
ROUTE_HOST=$(oc get route agent-host-direct -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$ROUTE_HOST" ]; then
  echo "  [PASS] Route: https://$ROUTE_HOST/"
  ((PASS++))
  EXT_STATUS=$(curl -so /dev/null -w '%{http_code}' --connect-timeout 5 \
    "https://$ROUTE_HOST/?tkn=${AGENT_HOST_TOKEN}" 2>/dev/null || echo "000")
  if [ "$EXT_STATUS" != "000" ]; then
    echo "  [PASS] Route reachable externally (HTTP $EXT_STATUS)"
    ((PASS++))
  else
    echo "  [WARN] Route not reachable externally"
    ((WARN++))
  fi
else
  echo "  [FAIL] No route found"
  ((FAIL++))
fi

# --- Entrypoint logs (last 20 lines) ---
echo ""
echo "Entrypoint logs (last 20 lines):"
exec_pod tail -20 /tmp/agent-host-logs.txt 2>/dev/null | sed 's/^/  /'

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed, $WARN warnings ==="
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Debug: oc exec -it $POD -c $CONTAINER -n $NAMESPACE -- bash"
  echo "Logs:  oc exec $POD -c $CONTAINER -n $NAMESPACE -- cat /tmp/agent-host-logs.txt"
  exit 1
fi
