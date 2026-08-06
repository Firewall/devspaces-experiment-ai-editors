#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/config.env" 2>/dev/null
NAMESPACE="${NAMESPACE:-rh-ee-mdemytte-dev}"

echo "=== Tearing down T3 Connect from namespace: $NAMESPACE ==="

oc delete devworkspace t3-connect-workspace -n "$NAMESPACE" 2>/dev/null
oc delete devworkspacetemplate t3-connect-editor -n "$NAMESPACE" 2>/dev/null

echo "Done."
