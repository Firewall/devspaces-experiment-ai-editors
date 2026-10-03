#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -f "$REPO_ROOT/config.env" ]; then
  echo "config.env not found. Set NAMESPACE in config.env before teardown."
  exit 1
fi
source "$REPO_ROOT/config.env"
NAMESPACE="${NAMESPACE:?Set NAMESPACE in config.env}"

echo "=== Tearing down Orca from namespace: $NAMESPACE ==="

oc delete devworkspace orca-workspace -n "$NAMESPACE" --ignore-not-found
oc delete devworkspacetemplate orca-editor -n "$NAMESPACE" --ignore-not-found
oc delete service orca-direct -n "$NAMESPACE" --ignore-not-found
oc delete route orca-direct -n "$NAMESPACE" --ignore-not-found

echo "Done."
