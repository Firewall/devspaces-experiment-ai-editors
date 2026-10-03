#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
teardown_editor "T3 Code" "t3-code-workspace" "t3-code-editor" "t3-code-direct"
