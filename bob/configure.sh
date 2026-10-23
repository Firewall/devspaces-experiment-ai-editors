#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=shared/deploy.sh
source "$REPO_ROOT/shared/deploy.sh"
load_config
if [ "$#" -ne 2 ]; then
  echo "Usage: ./bob/configure.sh /private/path/bob-api-key /path/to/.bob/settings/settings.json" >&2
  exit 1
fi
# Read credentials from files, never command arguments or rendered devfiles.
MANIFEST=$(node - "$1" "$2" <<'JS'
const fs = require('node:fs');
const key = fs.readFileSync(process.argv[2], 'utf8').trim();
const settings = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
if (!key) throw new Error('Bob API key file is empty');
if (settings.licenseConsent !== true) throw new Error('Review and accept the IBM license with Bob Shell first');
console.log(JSON.stringify({
  apiVersion:'v1', kind:'Secret', type:'Opaque',
  metadata:{name:'bob-credentials', labels:{
    'controller.devfile.io/mount-to-devworkspace':'true',
    'controller.devfile.io/watch-secret':'true'
  }, annotations:{
    'controller.devfile.io/mount-path':'/etc/secret/bob-credentials',
    'controller.devfile.io/mount-to-devworkspace-include':'bob-workspace',
    'controller.devfile.io/mount-on-start':'true'
  }},
  stringData:{BOB_API_KEY:key, 'settings.json':JSON.stringify({licenseConsent:true})}
}));
JS
)
printf '%s\n' "$MANIFEST" | oc apply -n "$NAMESPACE" -f -
echo "Bob credentials saved. Stop and start bob-workspace to load them."
