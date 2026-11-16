#!/bin/bash
# KiroCrew gateway entrypoint for a Dev Spaces workspace.

PERSIST="${PROJECTS_ROOT:-/projects}/.devspaces-kirocrew"
WORKDIR="${PROJECTS_ROOT:-/projects}"
umask 077

mkdir -p "$PERSIST" || exit 1
chmod 700 "$PERSIST" || exit 1

# OpenShift runs an arbitrary UID. Keep every writable path under /projects and
# point the gateway, kiro-cli, and their XDG caches at that home. KiroCrew keeps
# its state in ~/.kiro/crew, so HOME is the only override needed.
export HOME="$PERSIST"
export XDG_CONFIG_HOME="$PERSIST/.config"
export XDG_DATA_HOME="$PERSIST/.local/share"
export XDG_STATE_HOME="$PERSIST/.local/state"
export XDG_CACHE_HOME="$PERSIST/.cache"
export KIROCREW_PORT="${KIROCREW_PORT:-5476}"
export KIROCREW_BIND="${KIROCREW_BIND:-0.0.0.0}"

# The OpenShift Route host is only known at deploy time. The gateway reads
# KIROCREW_CORS_ORIGINS when it builds its allowed-origin set, which also feeds
# the DNS-rebinding Host barrier and the WebSocket handshake.
if [ -n "${KIROCREW_PUBLIC_ORIGIN:-}" ]; then
  export KIROCREW_CORS_ORIGINS="${KIROCREW_CORS_ORIGINS:+${KIROCREW_CORS_ORIGINS},}${KIROCREW_PUBLIC_ORIGIN}"
fi

# shellcheck source=shared/runtime.sh
source /usr/local/bin/shared-runtime.sh
setup_runtime /usr/local/bin/shared-bashrc.sh || exit 1

echo ""
echo "=== KiroCrew ==="
echo "Data home: $HOME/.kiro/crew"
echo "Dashboard login links are minted with: kirocrew token"
echo ""

cd "$WORKDIR" || exit 1

# The upstream entrypoint moves channel and model credentials into
# $KIROCREW_HOME/.env, decides the first-run sandbox posture, and execs the
# gateway under tini with --no-open.
exec /usr/local/bin/kirocrew-entrypoint gateway
