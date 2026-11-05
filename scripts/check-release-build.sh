#!/usr/bin/env bash
# Checks a Release build: the debug-only fixture data source isn't in it (#18), the
# widget extension is embedded and sandboxed, and the host app isn't sandboxed.
set -euo pipefail
APP="${1:?usage: check-release-build.sh <path to Agent Usage.app>}"
WIDGET="$APP/Contents/PlugIns/AgentUsageWidget.appex"

fail() { echo "check-release-build: $*" >&2; exit 1; }

[[ -d "$WIDGET" ]] || fail "the widget extension isn't embedded"

while IFS= read -r -d '' binary; do
  if strings -a "$binary" | grep -q "FixtureUsageProvider"; then
    fail "the fixture data source is in a Release binary: $binary"
  fi
done < <(find "$APP" -type f -perm -u+x -print0)

entitlements() { codesign -d --entitlements - --xml "$1" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || echo '{}'; }
[[ "$(entitlements "$WIDGET" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("com.apple.security.app-sandbox", False))')" == "True" ]] \
  || fail "the widget extension isn't sandboxed"
[[ "$(entitlements "$APP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("com.apple.security.app-sandbox", False))')" == "False" ]] \
  || fail "the host app is sandboxed"

echo "check-release-build: OK ($APP)"
