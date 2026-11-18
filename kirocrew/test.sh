#!/bin/bash
# End-to-end validation for the KiroCrew workspace.
# Run after deploy.sh completes.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -f "$REPO_ROOT/config.env" ]; then
  echo "config.env not found. Set NAMESPACE in config.env before testing."
  exit 1
fi
# shellcheck source=/dev/null
source "$REPO_ROOT/config.env"
NAMESPACE="${NAMESPACE:?Set NAMESPACE to your Dev Spaces user namespace in config.env}"
WS_NAME="kirocrew-workspace"
CONTAINER="kirocrew-runtime"
STATE_DIR="/projects/.devspaces-kirocrew/.kiro/crew"

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

echo "=== KiroCrew integration test ==="
echo ""

# --- Pod ---
echo "Pod:"
POD=$(oc get pods -n "$NAMESPACE" -l "controller.devfile.io/devworkspace_name=$WS_NAME" --no-headers 2>/dev/null | grep -v cleanup | grep -v Completed | awk '{print $1}')
if [ -z "$POD" ]; then
  echo "  [FAIL] No pod found for workspace $WS_NAME"
  echo ""
  echo "Run ./kirocrew/deploy.sh first."
  exit 1
fi
echo "  [PASS] Pod: $POD"
((PASS++))

check "Pod is Ready" oc wait --for=condition=Ready "pod/$POD" -n "$NAMESPACE" --timeout=10s

# --- Binaries ---
echo ""
echo "Binaries:"
if KIROCREW_VERSION=$(exec_pod kirocrew --version 2>&1); then
  echo "  [PASS] kirocrew: $(echo "$KIROCREW_VERSION" | head -1)"
  ((PASS++))
else
  echo "  [FAIL] kirocrew failed: $KIROCREW_VERSION"
  ((FAIL++))
fi

if KIRO_CLI_VERSION=$(exec_pod kiro-cli --version 2>&1); then
  echo "  [PASS] kiro-cli: $(echo "$KIRO_CLI_VERSION" | head -1)"
  ((PASS++))
else
  echo "  [FAIL] kiro-cli failed: $KIRO_CLI_VERSION"
  ((FAIL++))
fi

# --- State and gateway ---
echo ""
echo "Gateway:"
check "State directory exists" exec_pod test -d "$STATE_DIR"
check "config.json exists" exec_pod test -s "$STATE_DIR/config.json"
check "Gateway process is running" exec_pod pgrep -f "kirocrew gateway"

HEALTH=$(exec_pod curl -fsS "http://127.0.0.1:5476/api/health" 2>/dev/null || true)
if [ -n "$HEALTH" ]; then
  echo "  [PASS] Health endpoint answers"
  ((PASS++))
else
  echo "  [FAIL] Health endpoint did not answer"
  ((FAIL++))
fi

# --- Dashboard token ---
echo ""
echo "Dashboard token:"
TOKEN_URL=$(exec_pod kirocrew token --ttl 5m 2>/dev/null | grep -oE 'https?://[^[:space:]]*token=[^[:space:]]*' | head -n 1 || true)
if [ -n "$TOKEN_URL" ]; then
  echo "  [PASS] Login link minted"
  ((PASS++))
else
  echo "  [FAIL] Could not mint a login link"
  ((FAIL++))
fi

# --- Agent runtime sign-in ---
echo ""
echo "Agent runtime:"
WHOAMI=$(exec_pod kiro-cli whoami 2>&1 || true)
if [ -n "$WHOAMI" ] && ! echo "$WHOAMI" | grep -qiE 'not logged|sign in|error'; then
  echo "  [PASS] kiro-cli is signed in"
  ((PASS++))
else
  echo "  [WARN] kiro-cli is not signed in; chat sessions will not start"
  echo "         Run: oc exec -it $POD -c $CONTAINER -n $NAMESPACE -- kiro-cli login"
  ((WARN++))
fi

if exec_pod grep -q '"sandbox_allow_unsandboxed_exec": true' "$STATE_DIR/config.json" 2>/dev/null; then
  echo "  [INFO] Agent commands run unsandboxed; the container is the isolation boundary"
else
  echo "  [INFO] Agent commands use the inner sandbox, or are disabled if it is unavailable"
fi

# --- Route ---
echo ""
echo "Route:"
ROUTE_HOST=$(oc get route kirocrew-direct -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$ROUTE_HOST" ]; then
  echo "  [PASS] Route: https://$ROUTE_HOST/"
  ((PASS++))
  EXT_STATUS=$(curl -so /dev/null -w '%{http_code}' --connect-timeout 5 \
    "https://$ROUTE_HOST/api/health" 2>/dev/null || echo "000")
  if [ "$EXT_STATUS" = "200" ]; then
    echo "  [PASS] Route reachable externally (HTTP $EXT_STATUS)"
    ((PASS++))
  else
    echo "  [WARN] Route not reachable externally (HTTP $EXT_STATUS)"
    ((WARN++))
  fi
else
  echo "  [FAIL] No route found"
  ((FAIL++))
fi

# --- Startup logs ---
echo ""
echo "Startup logs (last 20 lines):"
oc logs "$POD" -c "$CONTAINER" -n "$NAMESPACE" --tail=20 2>/dev/null | sed 's/^/  /'

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed, $WARN warnings ==="
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Debug: oc exec -it $POD -c $CONTAINER -n $NAMESPACE -- bash"
  echo "Logs:  oc logs $POD -c $CONTAINER -n $NAMESPACE"
  exit 1
fi
