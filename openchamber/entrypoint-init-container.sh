#!/bin/bash
set -e

cp /usr/local/bin/openchamber-entrypoint.sh /openchamber/entrypoint.sh
cp /usr/local/bin/shared-runtime.sh /openchamber/runtime.sh
cp /usr/local/bin/shared-bashrc.sh /openchamber/bashrc.sh
cp /usr/local/bin/shared-discover-models.sh /openchamber/discover-models.sh
cp /opt/openchamber/redhat-dark.json /openchamber/redhat-dark.json
cp -r /opt/app-root/src/.npm-global /openchamber/npm-global
cp -r /usr/lib/google-cloud-sdk /openchamber/google-cloud-sdk

echo "OpenChamber injector complete"
