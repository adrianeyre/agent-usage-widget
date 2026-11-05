#!/usr/bin/env bash
# Builds, signs and packages a release (B5–B7). Called by semantic-release's prepare step:
#
#   scripts/build-release.sh <version>
#
# Writes dist/AgentUsage-<version>.zip (the .app, zipped with ditto) and its
# SHA-256 checksum file. The build number is the GitHub run number (B5).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: build-release.sh <version>}"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-0}"
DERIVED="${DERIVED_DATA:-build/DerivedData}"
APP="$DERIVED/Build/Products/Release/Agent Usage.app"
ZIP="AgentUsage-$VERSION.zip"

scripts/generate-project.sh
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage -configuration Release \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build | tail -n 20

if [[ "${AGENT_USAGE_SKIP_SIGNING:-}" == "1" ]]; then
  echo "build-release: AGENT_USAGE_SKIP_SIGNING=1, leaving the ad-hoc signature" >&2
else
  scripts/sign.sh "$APP"
fi
scripts/check-release-build.sh "$APP"

[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")" == "$BUILD_NUMBER" ]]

rm -rf dist && mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$ZIP"
(cd dist && shasum -a 256 "$ZIP" > "$ZIP.sha256")
cat "dist/$ZIP.sha256"
