#!/bin/bash
set -e

cp -r /opt/app-root/src/node_modules /t3code/node_modules
cp -r /usr/lib/google-cloud-sdk /t3code/google-cloud-sdk

echo "T3 Code injector complete"
