#!/usr/bin/env bash
# Throwaway probe for #16 after check 1 failed: setup tokens lack the user:profile scope
# that /api/oauth/usage and /api/oauth/profile need.
#
#   prototypes/claude-data-source/probe-headers.sh
#
# Checks whether ordinary API responses to a setup token carry the
# anthropic-ratelimit-unified-* headers (Session and Weekly utilisation and reset).
# It tries count_tokens first (no model output), then a 1-token message. It prints
# only status lines, the rate-limit headers and error messages. It never prints the
# token or reads Claude Code's own login (U6).
set -euo pipefail
exec > >(tee "$(dirname "$0")/last-run-headers.txt")

if [[ -n "${CLAUDE_SETUP_TOKEN:-}" ]]; then
  token="$CLAUDE_SETUP_TOKEN"
else
  read -rsp "Paste the token from 'claude setup-token' (input hidden): " token
  echo
fi

call() {
  local name="$1" url="$2" data="$3" body headers
  body="$(mktemp)"; headers="$(mktemp)"
  curl -sS -o "$body" -D "$headers" "$url" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -H "User-Agent: AgentUsage-probe" \
    -d "$data"
  echo "=== $name: $(head -1 "$headers" | tr -d '\r')"
  grep -i -E '^anthropic-ratelimit-unified' "$headers" | tr -d '\r' || echo "(no anthropic-ratelimit-unified headers)"
  python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1]))
except Exception:
    sys.exit()
e=d.get("error")
print("error:", e.get("type"), "-", e.get("message")) if e else print("ok:", ", ".join(sorted(d.keys())))' "$body"
  echo
  rm -f "$body" "$headers"
}

msg='{"model":"claude-haiku-5-5","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'
call "count_tokens (no output)" "https://api.anthropic.com/v1/messages/count_tokens" '{"model":"claude-haiku-5-5","messages":[{"role":"user","content":"hi"}]}'
call "messages, max_tokens 1" "https://api.anthropic.com/v1/messages" "$msg"
