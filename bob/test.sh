#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != --live ]; }; then
  echo "Usage: ./bob/test.sh [--live]" >&2
  exit 1
fi
wait_for_workspace bob-workspace 300s
oc exec -i "$POD" -c bob-runtime -n "$NAMESPACE" -- node --input-type=module - check < "$REPO_ROOT/bob/smoke.mjs"
if [ "${1:-}" = --live ]; then
  STATE=$(oc exec -i "$POD" -c bob-runtime -n "$NAMESPACE" -- node --input-type=module - start < "$REPO_ROOT/bob/smoke.mjs")
  echo "Bob wrote the marker. Restarting bob-workspace to check persistence..."
  oc patch devworkspace bob-workspace -n "$NAMESPACE" --type=merge -p '{"spec":{"started":false}}'
  oc wait devworkspace/bob-workspace -n "$NAMESPACE" --for=jsonpath='{.status.phase}'=Stopped --timeout=180s
  oc patch devworkspace bob-workspace -n "$NAMESPACE" --type=merge -p '{"spec":{"started":true}}'
  wait_for_workspace bob-workspace 300s
  # Deployment readiness may precede the application listener.
  for ((attempt=0; attempt<30; attempt++)); do
    if oc exec "$POD" -c bob-runtime -n "$NAMESPACE" -- node -e \
      'fetch("http://127.0.0.1:8000/healthz").then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))' >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  oc exec -i "$POD" -c bob-runtime -n "$NAMESPACE" -- node --input-type=module - resume "$STATE" < "$REPO_ROOT/bob/smoke.mjs"
fi
