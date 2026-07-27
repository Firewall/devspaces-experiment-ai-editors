#!/bin/bash
set -e

cp /usr/local/bin/openchamber-entrypoint.sh /openchamber/entrypoint.sh

# OpenChamber + OpenCode (both installed via npm global)
cp -r /opt/app-root/src/.npm-global /openchamber/npm-global

# gcloud CLI (for Vertex AI auth)
cp -r /usr/lib/google-cloud-sdk /openchamber/google-cloud-sdk

echo "OpenChamber injector complete"
