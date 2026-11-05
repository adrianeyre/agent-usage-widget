# Each Claude Account uses its own Claude Code folder, signed in from Agent Usage

ADR-0008 read Claude usage from the status line of the Owner's own Claude Code. That had two problems. Signing in had to happen in Claude Code, and a second account meant switching `/login` back and forth. The Owner asked to authenticate Claude Accounts in Agent Usage itself.

Claude Code can do both without the app ever touching a token:

- `claude auth login --claudeai`, run with `CLAUDE_CONFIG_DIR` set to a folder, signs that folder in through the browser. Claude Code keeps the login in its own Keychain item, `Claude Code-credentials-<hash of the folder>`, which is separate from the everyday `Claude Code-credentials`, and it refreshes the login itself. When the browser is already signed in to claude.ai, this finishes by itself in a few seconds. Otherwise Claude Code asks for a code, which the app passes on.
- `claude auth status --json` gives `email`, `orgId`, `orgName`, `subscriptionType` and `loggedIn`.
- `claude -p /usage --output-format json` is a **local command**: `num_turns` 0, `total_cost_usd` 0, about 0.4 s, and no model request, so polling spends none of the allowance. Its `result` text has `Current session: 3% used · resets Nov 5 at 4:39pm (Europe/London)` and `Current week (all models): 34% used · resets Nov 5 at 3pm (Europe/London)`.

So, as with Codex (ADR-0005), each Claude Account gets a **dedicated Claude Code folder owned by the app** (`Application Support/Agent Usage/claude/<account-id>/`). Add Account and Re-authorise run `claude auth login` there, the email comes from `auth status`, and every fetch runs `/usage` there. Removing the Account runs `claude auth logout`, which deletes that Keychain item, and then deletes the folder. The Owner's `~/.claude` is never used. The status line wrapper is removed, and the Owner's original status line is restored exactly.

## Consequences

- Any number of Claude Accounts, each with its own sign-in, and figures every 5 minutes whether or not Claude Code is in use.
- **Fragile:** the figures are parsed from `/usage`'s human-readable text. If Claude Code changes the wording, the parser returns `nil` or an unexpected-response error, never guessed figures (R6). A signed-out folder is recognised from `auth status` (`loggedIn: false`) and shows `Sign in required`.
- The `claude` CLI must be installed, and signed-in Claude Code folders count as devices or sessions on the Anthropic account.
- To sign in to a **different** account, the browser must not be signed in to the first one: sign out of claude.ai first, or use a private window.
- The login refreshes itself, so there's no `Re-authorise by` for Claude (U3).

Supersedes ADR-0008.
