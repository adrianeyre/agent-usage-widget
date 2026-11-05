#!/usr/bin/env bash
# Builds, signs and installs a local Debug build to /Applications, working around the
# widget gotchas in the README:
#
#   scripts/dev-install.sh [Debug|Release]
#
# - Gives every build a new CFBundleVersion. WidgetKit caches a widget extension's list of
#   widgets per version, so a rebuilt 0.0.0 (0) keeps showing the old widgets in the gallery.
# - Unregisters the copies Xcode leaves in build/DerivedData. Otherwise the gallery can offer
#   a stale build's widgets.
# - Restarts the widget extension and chronod so the new widgets load straight away.
# - Signs with scripts/sign.sh, so updates keep the same signer (no Keychain prompts, ADR-0004).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
DERIVED="${DERIVED_DATA:-build/DerivedData}"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
APP="$DERIVED/Build/Products/$CONFIG/Agent Usage.app"
INSTALLED="/Applications/Agent Usage.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

scripts/generate-project.sh >/dev/null
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsage -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build | tail -n 3
scripts/sign.sh "$APP"

osascript -e 'quit app "Agent Usage"' 2>/dev/null || true
sleep 1
pkill -x "Agent Usage" 2>/dev/null || true
pkill -x AgentUsageWidget 2>/dev/null || true
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"

# Only the installed copy should be registered.
for config in Debug Release; do
  copy="$PWD/$DERIVED/Build/Products/$config/Agent Usage.app"
  [[ -d "$copy" ]] || continue
  pluginkit -r "$copy/Contents/PlugIns/AgentUsageWidget.appex" 2>/dev/null || true
  "$LSREGISTER" -u "$copy" 2>/dev/null || true
done
"$LSREGISTER" -f "$INSTALLED"

open "$INSTALLED"
killall chronod 2>/dev/null || true
echo "Installed build $BUILD_NUMBER. Registered widget extensions:"
pluginkit -m -v -A -D -i com.adrianeyre.AgentUsage.Widget
