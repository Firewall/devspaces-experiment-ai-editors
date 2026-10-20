#!/bin/bash
set -euo pipefail
umask 077

PERSIST="${PROJECTS_ROOT:-/projects}/.devspaces-bob"
mkdir -p "$PERSIST/home" "$PERSIST/service"
chmod 700 "$PERSIST" "$PERSIST/home" "$PERSIST/service"
export HOME="$PERSIST/home"
export DATA_DIR="$PERSIST/service"
export BOB_WORKSPACE_DIR="${BOB_WORKSPACE_DIR:-${PROJECTS_ROOT:-/projects}/repo}"
mkdir -p "$HOME/.bob/settings" "$BOB_WORKSPACE_DIR"

# Keep the UI credential stable across workspace and container restarts.
TOKEN_FILE="$PERSIST/ui-token"
if [ ! -s "$TOKEN_FILE" ]; then
  node -e 'process.stdout.write(require("node:crypto").randomBytes(32).toString("hex"))' > "$TOKEN_FILE"
fi
chmod 600 "$TOKEN_FILE"
AUTH_TOKENS=$(node -e 'console.log(JSON.stringify({owner:require("node:fs").readFileSync(process.argv[1],"utf8").trim()}))' "$TOKEN_FILE")
export AUTH_TOKENS

if [ "${AGENT_BACKEND:-bob}" = opencode ]; then
  OPENCODE_CONFIG_CONTENT=$(node /usr/local/bin/opencode-config.mjs)
  export OPENCODE_CONFIG_CONTENT
  echo "Starting the OpenCode console with ${OPENCODE_MODEL:-opencode/glm-5.3-flash-free}."
else
# The optional Secret is mounted only into Bob workspaces by DevWorkspace.
BOB_CONFIG_DIR="${BOB_CONFIG_DIR:-/etc/secret/bob-credentials}"
if [ -s "$BOB_CONFIG_DIR/BOB_API_KEY" ]; then
  BOB_API_KEY=$(cat "$BOB_CONFIG_DIR/BOB_API_KEY")
  export BOB_API_KEY
fi
if [ -f "$BOB_CONFIG_DIR/settings.json" ]; then
  node -e '
    const fs = require("node:fs");
    const settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (settings.licenseConsent !== true) throw new Error("Accept the Bob license with Bob Shell before configuring this workspace");
    fs.writeFileSync(process.argv[2], JSON.stringify({licenseConsent:true}), {mode:0o600});
  ' "$BOB_CONFIG_DIR/settings.json" "$HOME/.bob/settings/settings.json"
fi
if [ -z "${BOB_API_KEY:-}" ]; then
  echo "Bob UI is available; live runs require Bob credentials. See bob/README.md."
fi
fi

cd /app
exec node dist/server.js
