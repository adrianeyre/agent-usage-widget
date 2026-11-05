#!/usr/bin/env bash
# Imports the `Agent Usage Self-Signed` certificate into a temporary keychain (B6, #14).
#
# Reads the two repo secrets from the environment:
#   SIGNING_CERTIFICATE_P12_BASE64   the .p12, base64-encoded
#   SIGNING_CERTIFICATE_PASSWORD     its password
#
# Prints nothing secret. Writes AGENT_USAGE_KEYCHAIN to $GITHUB_ENV (when set) so
# scripts/sign.sh finds the identity, and scripts/ci/delete-keychain.sh removes it.
# The keychain is added to the user's search list as well as passed to codesign with
# --keychain: on the macos-26 runner, codesign reports "no identity found" for a keychain
# that isn't in the search list. delete-keychain.sh's `security delete-keychain` takes it
# out of the list again.
set -euo pipefail

# No apostrophes in these messages: inside "${VAR:?...}" bash reads one as the start of a
# single-quoted string, which garbles the error.
missing=()
[[ -n "${SIGNING_CERTIFICATE_P12_BASE64:-}" ]] || missing+=(SIGNING_CERTIFICATE_P12_BASE64)
[[ -n "${SIGNING_CERTIFICATE_PASSWORD:-}" ]] || missing+=(SIGNING_CERTIFICATE_PASSWORD)
if (( ${#missing[@]} )); then
  msg="Missing repo secret(s): ${missing[*]}. Set them with scripts/create-certificate.sh --secrets-only (docs/guide/releasing.md)."
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::error title=Signing secrets missing::$msg"; else echo "$msg" >&2; fi
  exit 1
fi

TMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KEYCHAIN="${AGENT_USAGE_KEYCHAIN:-$TMP/agent-usage-signing.keychain-db}"
P12="$(mktemp "$TMP/agent-usage-cert.XXXXXX")"
trap 'rm -f "$P12"' EXIT

KEYCHAIN_PASSWORD="$(openssl rand -base64 24)"
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::add-mask::$KEYCHAIN_PASSWORD"; fi

printf '%s' "$SIGNING_CERTIFICATE_P12_BASE64" | base64 --decode > "$P12"

rm -f "$KEYCHAIN"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -f pkcs12 -P "$SIGNING_CERTIFICATE_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

# Put it first in the search list, keeping the keychains already there.
existing=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; line="${line#\"}"
  [[ -n "$line" && "$line" != "$KEYCHAIN" ]] && existing+=("$line")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN" ${existing[@]+"${existing[@]}"}

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "AGENT_USAGE_KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"
fi
echo "Imported the signing certificate into $KEYCHAIN"
security find-identity -p codesigning "$KEYCHAIN" | grep -E '^\s+[0-9]+\)' || true
