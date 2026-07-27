#!/bin/bash

source config.env 2>/dev/null
NAMESPACE="${NAMESPACE:-rh-ee-mdemytte-dev}"

echo "=== Tearing down T3 Code from namespace: $NAMESPACE ==="

oc delete devworkspace t3-code-workspace -n "$NAMESPACE" 2>/dev/null
oc delete devworkspacetemplate t3-code-editor -n "$NAMESPACE" 2>/dev/null
oc delete service t3-code-direct -n "$NAMESPACE" 2>/dev/null
oc delete route t3-code-direct -n "$NAMESPACE" 2>/dev/null

echo "Done."
