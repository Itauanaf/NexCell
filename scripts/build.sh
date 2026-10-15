#!/usr/bin/env bash
set -euo pipefail
rm -rf dist
mkdir -p dist/server dist/.openai
cp worker/index.js dist/server/index.js
cp .openai/hosting.json dist/.openai/hosting.json
cp -r migrations dist/migrations
