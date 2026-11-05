#!/usr/bin/env bash
# Generates AgentUsage.xcodeproj from project.yml with XcodeGen.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null; then
  echo "XcodeGen is required: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate --quiet
