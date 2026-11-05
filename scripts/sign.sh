#!/usr/bin/env bash
# Signs both targets with the self-signed certificate (ADR-0004, B6): the widget
# extension first, then the host app around it, each with its own entitlements.
#
#   scripts/sign.sh "<path>/Agent Usage.app" ["Agent Usage Self-Signed"]
#
# Set AGENT_USAGE_KEYCHAIN to look for the identity in a specific keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?usage: sign.sh <path to Agent Usage.app> [identity]}"
IDENTITY="${2:-${AGENT_USAGE_SIGN_IDENTITY:-Agent Usage Self-Signed}}"
WIDGET="$APP/Contents/PlugIns/AgentUsageWidget.appex"

# Locally, use the signing keychain from scripts/create-certificate.sh when it exists,
# unlocking it with its password from the login keychain (no prompt).
LOCAL_KEYCHAIN="$HOME/Library/Keychains/agent-usage-signing.keychain-db"
if [[ -z "${AGENT_USAGE_KEYCHAIN:-}" && -f "$LOCAL_KEYCHAIN" ]]; then
  AGENT_USAGE_KEYCHAIN="$LOCAL_KEYCHAIN"
  security unlock-keychain -p "$(security find-generic-password -s "Agent Usage signing keychain" -w)" "$LOCAL_KEYCHAIN"
fi

keychain_args=()
if [[ -n "${AGENT_USAGE_KEYCHAIN:-}" ]]; then
  keychain_args=(--keychain "$AGENT_USAGE_KEYCHAIN")
  # Sign by hash, so an older certificate with the same name elsewhere can't make it ambiguous.
  hash="$(security find-identity -p codesigning "$AGENT_USAGE_KEYCHAIN" | awk -v n="\"$IDENTITY\"" 'index($0, n) {print $2; exit}')"
  [[ -n "$hash" ]] && IDENTITY="$hash"
fi

sign() {
  codesign --force --sign "$IDENTITY" ${keychain_args[@]+"${keychain_args[@]}"} --timestamp=none \
    --generate-entitlement-der --entitlements "$2" "$1"
}

sign "$WIDGET" App/Widget/AgentUsageWidget.entitlements
sign "$APP" App/HostApp/AgentUsage.entitlements

codesign --verify --deep --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "^Authority=|^Identifier=" || true
codesign -dvv "$WIDGET" 2>&1 | grep -E "^Authority=|^Identifier=" || true
