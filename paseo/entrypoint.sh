#!/bin/bash
# Paseo daemon entrypoint for a Dev Spaces workspace.

PERSIST="${PROJECTS_ROOT:-/projects}/.devspaces-paseo"
WORKDIR="${PROJECTS_ROOT:-/projects}"
umask 077

mkdir -p "$PERSIST/home" "$PERSIST/paseo-home" "$PERSIST/gcloud" || exit 1
chmod 700 "$PERSIST" || exit 1

export HOME="$PERSIST/home"
export PASEO_HOME="$PERSIST/paseo-home"
export SHELL=/bin/bash
export CLOUDSDK_CONFIG="$PERSIST/gcloud"
export PATH="/usr/lib/google-cloud-sdk/bin:${PATH}"

# shellcheck source=shared/runtime.sh
source /usr/local/bin/shared-runtime.sh
setup_runtime /usr/local/bin/shared-bashrc.sh || exit 1

mkdir -p "$HOME/.config" "$HOME/.local/share" "$HOME/.local/state"

# KServe discovery configures OpenCode, which Paseo runs as an agent. Keep
# OpenCode's default tools and permissions, as for Orca.
if [ -f /usr/local/bin/shared-discover-models.sh ]; then
  bash /usr/local/bin/shared-discover-models.sh \
    "${WORKDIR}/opencode.json" agent
fi
if [ -s "${WORKDIR}/opencode.json" ]; then
  export OPENCODE_CONFIG="${WORKDIR}/opencode.json"
fi

# Paseo hashes PASEO_PASSWORD at startup, so exporting the persisted value on
# every launch keeps the password stable across workspace restarts.
if [ -z "$PASEO_PASSWORD" ]; then
  if [ -s "$PERSIST/password.txt" ]; then
    PASEO_PASSWORD=$(cat "$PERSIST/password.txt")
  else
    PASEO_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 24)
  fi
fi
if [ -z "$PASEO_PASSWORD" ]; then
  echo "Unable to create a Paseo password" >&2
  exit 1
fi
printf '%s\n' "$PASEO_PASSWORD" > "$PERSIST/password.txt" || exit 1
chmod 600 "$PERSIST/password.txt" || exit 1
export PASEO_PASSWORD

export PASEO_LISTEN="${PASEO_LISTEN:-0.0.0.0:6767}"
export PASEO_WEB_UI_ENABLED=true

echo ""
echo "=== Paseo ==="
echo "Password saved. Retrieve it with deploy.sh or oc exec."
echo ""

cd "$WORKDIR" || exit 1

# Paseo records the host that wrote its PID lock, but decides staleness from the
# recorded PID alone. A lock left behind by an earlier pod can name a PID that an
# unrelated process now holds in this pod, and startup then aborts with "Another
# Paseo daemon is already running" on every retry. Nothing else can be running
# when this script starts, so keep a lock only when this host wrote it and its
# PID still belongs to a Paseo supervisor.
PID_LOCK="$PASEO_HOME/paseo.pid"
if [ -s "$PID_LOCK" ]; then
  if ! node -e '
    const fs = require("node:fs");
    try {
      const lock = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const cmdline = fs.readFileSync("/proc/" + Number(lock.pid) + "/cmdline", "utf8");
      process.exit(lock.hostname === process.argv[2] && cmdline.includes("supervisor-entrypoint") ? 0 : 1);
    } catch {
      process.exit(1);
    }
  ' "$PID_LOCK" "$(hostname)" 2>/dev/null; then
    echo "Removing a stale Paseo PID lock." >&2
    rm -f "$PID_LOCK" || exit 1
  fi
fi

SERVER_ENTRY=$(cat /etc/paseo-server-entry) || exit 1
if [ ! -f "$SERVER_ENTRY" ]; then
  echo "Paseo server entry not found: $SERVER_ENTRY" >&2
  exit 1
fi

# The supervisor restarts its worker on crash. Restart the supervisor itself
# only if it exits, matching the other integrations' watchdogs.
while true; do
  node "$SERVER_ENTRY" &
  PASEO_PID=$!
  wait "$PASEO_PID"
  STATUS=$?
  echo "Paseo exited ($STATUS), restarting in 2s..." >&2
  sleep 2
done
