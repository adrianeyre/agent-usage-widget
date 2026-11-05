#!/usr/bin/env bash
# Deletes the temporary signing keychain. Runs even when the job fails (#14).
set -uo pipefail
KEYCHAIN="${AGENT_USAGE_KEYCHAIN:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/agent-usage-signing.keychain-db}"
if [[ -f "$KEYCHAIN" ]]; then
  security delete-keychain "$KEYCHAIN" && echo "Deleted $KEYCHAIN"
else
  echo "No signing keychain to delete"
fi
