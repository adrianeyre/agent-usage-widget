---
status: superseded by ADR-0011
---

# Claude usage comes from Claude Code's status line feed

ADR-0003 assumed a one-year `claude setup-token` token could read usage. The #16 prototype showed it can't. `/api/oauth/usage` and `/api/oauth/profile` both answer 403 *OAuth token does not meet scope requirement user:profile*. An ordinary API call with the token doesn't help either: `count_tokens` returns no rate-limit headers, and a 1-token message is refused with 429.

So the app uses the only documented source of Claude usage (PRD §7.1): the `rate_limits` object that Claude Code passes to its status line command. That object has `five_hour` and `seven_day`, each with `used_percentage` (0–100) and `resets_at` (Unix seconds).

- **Each Claude Account belongs to a Claude Code configuration directory**: `~/.claude` by default, or the folder `CLAUDE_CONFIG_DIR` points at. **Several Accounts can share one directory** when the Owner switches between them with `/login`. The wrapper saves each update under the account signed in at that moment (`oauthAccount.emailAddress` and `organizationUuid`), so each Account keeps its own figures, and an Account goes Stale while it isn't the one signed in.
- **Adding the Account** backs up that directory's `settings.json`. It then sets `statusLine.command` to the app's wrapper (`host/claude-feed/agent-usage-statusline <account-id>`) and keeps the Owner's other status line options. The wrapper uses macOS's own `plutil` to save **only** `rate_limits` to `host/claude-feed/<account-id>.json`. It then passes the full input to the Owner's original status line command, so the status line looks the same.
- **The Account email and organisation** come from `oauthAccount.emailAddress`, `organizationUuid` and `organizationName` in Claude Code's `.claude.json` (`~/.claude.json` for the default directory). Those fields are account metadata, not a credential.
- **Re-authorise** reinstalls the wrapper, in case something replaced it. If the wrapper is missing, the Account shows `Sign in required`, and Re-authorise fixes it.
- **Removing an Account** deletes its saved figures. Removing the **last** Account that uses a directory puts the original `statusLine` back, or removes it if there wasn't one.

**Hard rule (U6), unchanged:** the app never reads, refreshes or rewrites Claude Code's login. It holds **no Claude Authorisation at all**: no token, no Keychain item, nothing that expires.

## Considered Options

- **The app runs its own Anthropic OAuth sign-in** with the `user:profile` scope. Rejected: it would reuse Claude Code's undocumented OAuth client from another app.
- **Borrowing Claude Code's login** (ADR-0001). Still rejected by U6.
- **Pausing the Claude Provider.** Rejected because a documented source exists.

## Consequences

- Figures update only while Claude Code is running with that configuration directory, each time it gets an API response. The Snapshot's `fetchedAt` is when Claude Code last reported, so an Account goes Stale 30 minutes after Claude Code stops answering. The Pace marker keeps moving (R2), and a window whose reset has passed is treated as reset (§10).
- `rate_limits` exists only for Pro, Max and Ultra subscribers, and only after the first API response in a session. Until then, the Account shows "No usage reported yet".
- There's no `Re-authorise by` for Claude (U3).
- If Claude Code changes the `rate_limits` fields, the parser returns `nil`s or an error (§7.3).
- The app edits Claude Code's `settings.json`. Every edit keeps the other keys and makes a `.agent-usage-backup` copy first.

Supersedes ADR-0003.
