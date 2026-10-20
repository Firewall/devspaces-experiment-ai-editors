#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
teardown_editor Bob bob-workspace bob-editor bob-direct
echo "Credential and image pull Secrets are retained. Remove them separately if no longer needed."
