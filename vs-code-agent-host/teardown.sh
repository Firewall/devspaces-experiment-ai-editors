#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
teardown_editor "VS Code Agent Host" "vs-code-agent-host-workspace" "vs-code-agent-host-editor" "agent-host-direct"
