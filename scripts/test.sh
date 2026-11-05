#!/usr/bin/env bash
# Builds both targets in Debug and Release and runs every unit test (B2).
# Used by CI on pull requests and before every release.
set -euo pipefail
cd "$(dirname "$0")/.."
DERIVED="${DERIVED_DATA:-build/DerivedData}"

echo "::group::Unit tests (AgentUsageCore and app logic)"
swift test --package-path AgentUsageCore
echo "::endgroup::"

scripts/generate-project.sh

for config in Debug Release; do
  echo "::group::xcodebuild $config"
  xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage -configuration "$config" \
    -derivedDataPath "$DERIVED" build | tail -n 20
  echo "::endgroup::"
done

scripts/check-release-build.sh "$DERIVED/Build/Products/Release/Agent Usage.app"
