#!/usr/bin/env bash
# Installs a release of Agent Usage (B9). The only supported way to install.
#
#   scripts/install.sh            # the latest release
#   scripts/install.sh 1.2.0      # a named version
#
# Downloads with `gh release download`, which doesn't set the quarantine flag, checks the
# SHA-256, quits the running host app, replaces /Applications/Agent Usage.app and relaunches it.
#
# Environment overrides:
#   AGENT_USAGE_REPO          owner/repo to download from
#   AGENT_USAGE_INSTALL_DIR   where to install (default /Applications)
#   AGENT_USAGE_ASSETS_DIR    use already-downloaded assets from this folder instead of gh (testing)
#   AGENT_USAGE_NO_LAUNCH=1   don't quit or relaunch the app (testing)
set -euo pipefail

REPO="${AGENT_USAGE_REPO:-adrianeyre/agent-usage-widget}"
INSTALL_DIR="${AGENT_USAGE_INSTALL_DIR:-/Applications}"
APP_NAME="Agent Usage"
BUNDLE_ID="com.adrianeyre.AgentUsage"
DEST="$INSTALL_DIR/$APP_NAME.app"
VERSION="${1:-}"

die() { echo "install.sh: $*" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/download" "$WORK/unpacked"

if [[ -n "${AGENT_USAGE_ASSETS_DIR:-}" ]]; then
  cp "$AGENT_USAGE_ASSETS_DIR"/AgentUsage-*.zip "$AGENT_USAGE_ASSETS_DIR"/AgentUsage-*.zip.sha256 "$WORK/download/"
else
  command -v gh >/dev/null || die "the GitHub CLI (gh) is required: brew install gh"
  args=(--repo "$REPO" --dir "$WORK/download" --pattern 'AgentUsage-*.zip' --pattern 'AgentUsage-*.zip.sha256')
  if [[ -n "$VERSION" ]]; then
    echo "Downloading Agent Usage ${VERSION}…"
    gh release download "v${VERSION#v}" "${args[@]}"
  else
    echo "Downloading the latest Agent Usage release…"
    gh release download "${args[@]}"
  fi
fi

shopt -s nullglob
zips=("$WORK"/download/AgentUsage-*.zip)
[[ ${#zips[@]} -eq 1 ]] || die "expected one AgentUsage-*.zip in the release, found ${#zips[@]}"
ZIP="${zips[0]}"
SUM="$ZIP.sha256"
[[ -f "$SUM" ]] || die "the release has no checksum file for $(basename "$ZIP")"

echo "Checking the SHA-256…"
expected="$(awk '{print $1}' "$SUM")"
actual="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
[[ -n "$expected" && "$expected" == "$actual" ]] \
  || die "checksum mismatch for $(basename "$ZIP"): expected $expected, got $actual. Nothing was installed."

ditto -x -k "$ZIP" "$WORK/unpacked"
NEW="$WORK/unpacked/$APP_NAME.app"
[[ -d "$NEW" ]] || die "the zip doesn't contain $APP_NAME.app"
codesign --verify --deep --strict "$NEW" || die "the downloaded app's signature is invalid. Nothing was installed."

if [[ "${AGENT_USAGE_NO_LAUNCH:-}" != "1" ]] && pgrep -xq "$APP_NAME"; then
  echo "Quitting ${APP_NAME}…"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in {1..20}; do pgrep -xq "$APP_NAME" || break; sleep 0.5; done
  pkill -x "$APP_NAME" 2>/dev/null || true
fi

echo "Installing to ${DEST}…"
mkdir -p "$INSTALL_DIR"
if [[ -d "$DEST" ]]; then
  rm -rf "$DEST.previous"
  mv "$DEST" "$DEST.previous"
fi
if ditto "$NEW" "$DEST"; then
  rm -rf "$DEST.previous"
else
  rm -rf "$DEST"
  [[ -d "$DEST.previous" ]] && mv "$DEST.previous" "$DEST"
  die "couldn't copy the app; the previous version was put back"
fi

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DEST/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$DEST/Contents/Info.plist")"
echo "Installed Agent Usage $version (build $build)."

if [[ "${AGENT_USAGE_NO_LAUNCH:-}" != "1" ]]; then
  open "$DEST"
fi
