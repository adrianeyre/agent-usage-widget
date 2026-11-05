#!/usr/bin/env bash
# Creates the `Agent Usage Self-Signed` code-signing certificate (ADR-0004) in its own
# keychain, so signing never depends on the login keychain's password.
#
#   scripts/create-certificate.sh [--update-secrets]
#   scripts/create-certificate.sh --secrets-only   # set the repo secrets from the existing backup
#
# - Makes a 10-year RSA certificate with the code-signing extended key usage.
# - Keeps it in ~/Library/Keychains/agent-usage-signing.keychain-db, with a random password
#   stored as the login keychain item "Agent Usage signing keychain". scripts/sign.sh finds
#   both, so local signing needs no prompt.
# - Keeps a backup .p12 in ~/Library/Application Support/Agent Usage Signing/ (mode 600),
#   with its random password stored as the login keychain item "Agent Usage signing p12".
# - With --update-secrets, sets the two repo secrets CI signs with (B6).
#
# Prints no secret. Refuses to run if the signing keychain already exists.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Agent Usage Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/agent-usage-signing.keychain-db"
BACKUP_DIR="$HOME/Library/Application Support/Agent Usage Signing"
P12="$BACKUP_DIR/AgentUsage.p12"
OPENSSL=/usr/bin/openssl   # LibreSSL: its .p12 defaults are ones `security import` accepts.

if [[ "${1:-}" == "--secrets-only" ]]; then
  [[ -f "$P12" ]] || { echo "No backup at $P12. Run without --secrets-only first." >&2; exit 1; }
  base64 -i "$P12" | gh secret set SIGNING_CERTIFICATE_P12_BASE64
  security find-generic-password -s "Agent Usage signing p12" -w | tr -d '\n' | gh secret set SIGNING_CERTIFICATE_PASSWORD
  echo "Updated the SIGNING_CERTIFICATE_P12_BASE64 and SIGNING_CERTIFICATE_PASSWORD secrets"
  exit 0
fi

if [[ -e "$KEYCHAIN" ]]; then
  echo "$KEYCHAIN already exists. Delete it first to make a new certificate." >&2
  exit 1
fi

umask 077
mkdir -p "$BACKUP_DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

P12_PASSWORD="$("$OPENSSL" rand -base64 24)"
KEYCHAIN_PASSWORD="$("$OPENSSL" rand -base64 24)"
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$P12" -passout "pass:$P12_PASSWORD"

# Passwords go in the login keychain. Adding an item needs no keychain password.
security add-generic-password -U -a "$USER" -s "Agent Usage signing keychain" -w "$KEYCHAIN_PASSWORD" -T /usr/bin/security
security add-generic-password -U -a "$USER" -s "Agent Usage signing p12" -w "$P12_PASSWORD" -T /usr/bin/security

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # no auto-lock
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -f pkcs12 -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

HASH="$("$OPENSSL" x509 -in "$WORK/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)"
echo "Created \"$NAME\" ($HASH), valid until $("$OPENSSL" x509 -in "$WORK/cert.pem" -noout -enddate | cut -d= -f2)"
echo "Keychain: $KEYCHAIN"
echo "Backup:   $P12"

if [[ "${1:-}" == "--update-secrets" ]]; then
  base64 -i "$P12" | gh secret set SIGNING_CERTIFICATE_P12_BASE64
  printf '%s' "$P12_PASSWORD" | gh secret set SIGNING_CERTIFICATE_PASSWORD
  echo "Updated the SIGNING_CERTIFICATE_P12_BASE64 and SIGNING_CERTIFICATE_PASSWORD secrets"
fi
