# DevSpaces T3 Code — Agent Guidelines

## Deploying

Each editor directory (t3-code, openchamber, orca, openclaw, vs-code-agent-host) contains a `deploy.sh` script that handles the full lifecycle: build, push, register, and workspace creation. Always suggest `deploy.sh` before individual Makefile targets.

OpenClaw requires Node 24.22 or newer, so it builds on the upstream OpenClaw image instead of the universal developer image the other editors inject into.

Teardown is handled by `teardown.sh` in the same directory.
