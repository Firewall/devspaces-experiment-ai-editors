#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -f "$REPO_ROOT/config.env" ]; then
  echo "config.env not found. Set NAMESPACE in config.env before teardown."
  exit 1
fi
source "$REPO_ROOT/config.env"
NAMESPACE="${NAMESPACE:?Set NAMESPACE to your Dev Spaces user namespace in config.env}"

echo "=== Tearing down VS Code Agent Host from namespace: $NAMESPACE ==="

oc delete devworkspace vs-code-agent-host-workspace -n "$NAMESPACE" --ignore-not-found
oc delete devworkspacetemplate vs-code-agent-host-editor -n "$NAMESPACE" --ignore-not-found
oc delete service agent-host-direct -n "$NAMESPACE" --ignore-not-found
oc delete route agent-host-direct -n "$NAMESPACE" --ignore-not-found

echo "Done."
