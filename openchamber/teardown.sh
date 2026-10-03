#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -f "$REPO_ROOT/config.env" ]; then
  echo "config.env not found. Set NAMESPACE in config.env before teardown."
  exit 1
fi
source "$REPO_ROOT/config.env"
NAMESPACE="${NAMESPACE:?Set NAMESPACE to your Dev Spaces user namespace in config.env}"

echo "=== Tearing down OpenChamber from namespace: $NAMESPACE ==="

oc delete devworkspace openchamber-workspace -n "$NAMESPACE" --ignore-not-found
oc delete devworkspacetemplate openchamber-editor -n "$NAMESPACE" --ignore-not-found
oc delete service openchamber-direct -n "$NAMESPACE" --ignore-not-found
oc delete route openchamber-direct -n "$NAMESPACE" --ignore-not-found

echo "Done."
