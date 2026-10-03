#!/bin/bash
# Discovers KServe InferenceServices and generates chatLanguageModels.json for VS Code BYOK.

umask 077

NS="${REDHAT_AI_NAMESPACE:-sandbox-shared-models}"
OUT="${1:-${PROJECTS_ROOT:-/projects}/chatLanguageModels.json}"

command -v oc &>/dev/null || { echo "discover-models-vscode: oc not found, skipping"; exit 0; }

NAMES=$(oc get isvc -n "$NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
[ -z "$NAMES" ] && { echo "discover-models-vscode: no InferenceServices in $NS"; exit 0; }

TOKEN=$(cat /run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null) \
  || TOKEN=$(oc whoami -t 2>/dev/null) \
  || { echo "discover-models-vscode: no auth token"; exit 0; }

SERVICE_CA=/run/secrets/kubernetes.io/serviceaccount/service-ca.crt
[ -f "$SERVICE_CA" ] && TLS=(--cacert "$SERVICE_CA") || TLS=(-k)

PROBES="["
SEP=""
for NAME in $NAMES; do
  URL="https://${NAME}-predictor.${NS}.svc.cluster.local:8443/v1"
  RESP=$(curl -sf "${TLS[@]}" -H "Authorization: Bearer $TOKEN" \
    --connect-timeout 5 "$URL/models" 2>/dev/null) || continue
  PROBES+="${SEP}{\"isvc\":\"$NAME\",\"url\":\"$URL\",\"resp\":$RESP}"
  SEP=","
done
PROBES+="]"

[ "$PROBES" = "[]" ] && { echo "discover-models-vscode: no reachable models"; exit 0; }

TOKEN_FILE="/run/secrets/kubernetes.io/serviceaccount/token"

PROBES="$PROBES" TOKEN_FILE="$TOKEN_FILE" node - "$OUT" <<'EOF'
const fs = require('fs');
const data = JSON.parse(process.env.PROBES);
const tokenFile = process.env.TOKEN_FILE;
const models = [];

for (const { isvc, url, resp } of data) {
  const m = resp.data && resp.data[0];
  if (!m) continue;

  const key = isvc.replace(/^isvc-/, '');
  const label = key
    .split('-')
    .map(w =>
      /^(fp|bf)\d+$/i.test(w) ? `(${w.toUpperCase()})` :
      /^v\d/.test(w) ? w :
      w.charAt(0).toUpperCase() + w.slice(1)
    )
    .join(' ')
    .replace(/ \(/, ' (');

  models.push({
    id: m.id,
    name: label,
    url: `${url}/chat/completions`,
    toolCalling: true,
    maxInputTokens: m.max_model_len || 65536,
    maxOutputTokens: 8192,
  });
}

if (models.length === 0) process.exit(0);

// Read the SA token to use as API key
let apiKey = '';
try { apiKey = fs.readFileSync(tokenFile, 'utf8').trim(); } catch {}

const config = [{
  name: 'Red Hat AI',
  vendor: 'customendpoint',
  apiKey: apiKey,
  apiType: 'chat-completions',
  models: models,
}];

// This file contains a service account credential, including on existing volumes.
if (fs.existsSync(process.argv[2])) fs.chmodSync(process.argv[2], 0o600);
fs.writeFileSync(process.argv[2], JSON.stringify(config, null, 2) + '\n', { mode: 0o600 });
fs.chmodSync(process.argv[2], 0o600);
console.error(`discover-models-vscode: wrote ${models.length} model(s) to ${process.argv[2]}`);
EOF
