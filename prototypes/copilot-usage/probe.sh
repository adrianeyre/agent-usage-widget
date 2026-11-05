#!/usr/bin/env bash
# Throwaway probe for #27 (PRD §11, Copilot checks). Run it on the Owner's Mac.
#
#   prototypes/copilot-usage/probe.sh
#
# It asks for a fine-grained PAT (no repository access, account permission "Plan: read"
# only) without echoing it, then calls the endpoints the Copilot Provider uses. It prints
# each status, the token-expiry and accepted-permissions headers, and the body. It never
# reads gh's own login (U6).
set -euo pipefail
# Everything printed below is also saved (token-free) to last-run.txt next to this script.
exec > >(tee "$(dirname "$0")/last-run.txt")

if [[ -n "${COPILOT_PAT:-}" ]]; then
  token="$COPILOT_PAT"
else
  read -rsp "Paste the fine-grained token (input hidden): " token
  echo
fi
[[ "$token" == github_pat_* ]] || echo "warning: that doesn't start with github_pat_" >&2

call() {
  local name="$1" url="$2" body headers
  body="$(mktemp)"; headers="$(mktemp)"
  curl -sS -o "$body" -D "$headers" "$url" \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "User-Agent: AgentUsage-probe"
  echo "=== $name: $(head -1 "$headers" | tr -d '\r')"
  grep -i -E '^(github-authentication-token-expiration|x-accepted-github-permissions):' "$headers" | tr -d '\r' || true
  python3 -m json.tool < "$body" 2>/dev/null | grep -v analytics_tracking_id || cat "$body"
  echo
  rm -f "$body" "$headers"
}

call "Usage (quota_snapshots, quota_reset_date_utc)" "https://api.github.com/copilot_internal/user"
call "Username (PV6)" "https://api.github.com/user"
call "Primary email, if the token may read it (PV6)" "https://api.github.com/user/emails"
login="$(curl -sS https://api.github.com/user -H "Authorization: Bearer $token" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("login",""))')"
[[ -n "$login" ]] && call "Official AI credits report, for comparison" "https://api.github.com/users/$login/settings/billing/ai_credit/usage"

cat <<'NOTE'
Record for #27:
  - Does copilot_internal/user answer 200 to a fine-grained PAT with only Plan: read?
  - Is github-authentication-token-expiration present?
  - Can /user/emails be read, or only the username?
NOTE
