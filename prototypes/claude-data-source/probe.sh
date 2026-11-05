#!/usr/bin/env bash
# Throwaway probe for #16 (PRD §11 checks 1, 2 and 4). Run it on the Owner's Mac.
#
#   prototypes/claude-data-source/probe.sh
#
# It asks for a token from `claude setup-token` without echoing it, calls the two
# endpoints the Claude Provider uses, and prints the HTTP status and the response with
# anything token-like hidden. It never reads Claude Code's own login (U6).
set -euo pipefail
# Everything printed below is also saved (token-free) to last-run.txt next to this script.
exec > >(tee "$(dirname "$0")/last-run.txt")

if [[ -n "${CLAUDE_SETUP_TOKEN:-}" ]]; then
  token="$CLAUDE_SETUP_TOKEN"
else
  read -rsp "Paste the token from 'claude setup-token' (input hidden): " token
  echo
fi
[[ "$token" == sk-ant-oat01-* ]] || echo "warning: that doesn't start with sk-ant-oat01-" >&2

redact() { sed -E 's/sk-ant-[A-Za-z0-9]+-[A-Za-z0-9_-]+/sk-ant-…(hidden)/g'; }

call() {
  local name="$1" url="$2" body status
  body="$(mktemp)"
  status="$(curl -sS -o "$body" -w '%{http_code}' "$url" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Accept: application/json" \
    -H "User-Agent: AgentUsage-probe")"
  echo "=== $name: HTTP $status"
  (python3 -m json.tool < "$body" 2>/dev/null || cat "$body") | redact
  echo
  rm -f "$body"
}

call "Check 1: usage (Session and Weekly, with reset times)" "https://api.anthropic.com/api/oauth/usage"
call "Check 2: profile (email and organisation)" "https://api.anthropic.com/api/oauth/profile"

cat <<'NOTE'
Record for #16:
  1. Does the usage call return five_hour and seven_day, each with utilization and resets_at?
     Is utilization 0-100 or 0-1?
  2. Does the profile call return account.email_address and organization.uuid/name?
  4. Revoke the token (claude.ai → Settings → Claude Code / connected apps), run this again
     and note the status and body. The app treats 401 and 403 as Sign in required.
Check 3 is done in the app: Manage Accounts → + → Run claude setup-token.
NOTE
