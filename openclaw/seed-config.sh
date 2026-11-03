#!/bin/bash
# Seed or merge the OpenClaw gateway config without discarding Control UI edits.
# Usage: seed-config.sh CONFIG [PUBLIC_ORIGIN] [TRUSTED_PROXIES] [WORKSPACE]
set -e

CONFIG="${1:?seed-config: config path required}"
ORIGIN="${2:-}"
PROXIES="${3:-}"
WORKSPACE="${4:-/projects}"

node - "$CONFIG" "$ORIGIN" "$PROXIES" "$WORKSPACE" <<'EOF'
const fs = require('fs');
const path = require('path');

const [configPath, origin, proxies, workspace] = process.argv.slice(2);

let config = {};
if (fs.existsSync(configPath)) {
  try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (error) {
    console.error(`seed-config: ${configPath} is not valid JSON: ${error.message}`);
    process.exit(1);
  }
  if (!config || typeof config !== 'object' || Array.isArray(config)) {
    console.error(`seed-config: ${configPath} must contain a JSON object`);
    process.exit(1);
  }
}

config.gateway = config.gateway || {};
config.gateway.mode = 'local';
config.gateway.bind = 'lan';
config.gateway.port = 18789;
config.gateway.auth = config.gateway.auth || {};
config.gateway.auth.mode = config.gateway.auth.mode || 'token';
config.gateway.controlUi = config.gateway.controlUi || {};
config.gateway.controlUi.enabled = true;

// The Route host is only known at deploy time, so it wins over a stale value.
if (origin) config.gateway.publicOrigin = origin;

// OpenClaw rejects proxied requests unless the proxy source is trusted.
// config.env is the source of truth for this list.
const proxyList = proxies.split(/[,\s]+/).filter(Boolean);
if (proxyList.length) config.gateway.trustedProxies = proxyList;

config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
if (!config.agents.defaults.workspace) config.agents.defaults.workspace = workspace;

// A workspace stops when idle, so scheduled jobs would replay on restart.
// cron.skipMissedJobs defaults to false, which runs every missed slot at once.
if (!config.cron) config.cron = { enabled: false };

fs.mkdirSync(path.dirname(configPath), { recursive: true, mode: 0o700 });
fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n', { mode: 0o600 });
fs.chmodSync(configPath, 0o600);
EOF
