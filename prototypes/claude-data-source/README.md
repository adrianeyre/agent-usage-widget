# Prototype: Claude data source (#16)

Answers PRD §11 checks 1–4 on the Owner's Mac (macOS 27.0.1), 5 November 2026.

## Result: check 1 failed, so the Claude MVP was re-grilled

| Check | Answer |
|-------|--------|
| 1. A setup token reads Session and Weekly usage | **No.** `GET /api/oauth/usage` → **403** `permission_error`: *OAuth token does not meet scope requirement user:profile* (`oauth_scope_insufficient`). `probe-headers.sh`: `/v1/messages/count_tokens` → 200 with **no** `anthropic-ratelimit-unified-*` headers. `/v1/messages` (1 token) → **429** `rate_limit_error`, also with no headers. |
| 2. It reads the Account email and organisation | **No.** `GET /api/oauth/profile` → **403**: *does not meet scope requirement any_of(user:profile, user:office)*. |
| 3. The host app can run `claude setup-token` and capture the token | Moot after check 1. The setup-token code was removed. |
| 4. What a fetch returns once the token is revoked | Moot after check 1. |

Following PRD §11, a new grilling session chose **Claude Code's status line feed** (ADR-0008, superseding ADR-0003):

- Each Claude Account is one Claude Code configuration directory.
- The app puts `agent-usage-statusline <account-id>` in front of the Owner's status line. It saves only `rate_limits` (using `plutil`), then runs the original command with the same input.
- The email and organisation come from `oauthAccount` in `.claude.json`. That's metadata, not the login.
- The app holds no Claude token.

`ProviderTests.swift` runs the real wrapper with `/bin/sh` against a scratch configuration. It checks that the Owner's status line output is unchanged, that only `rate_limits` is saved, and that removal restores the original.

The probes (`probe.sh`, `probe-headers.sh`) are kept as the record. Their output goes to the git-ignored `last-run*.txt`.
