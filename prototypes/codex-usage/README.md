# Prototype: Codex usage from a dedicated Codex home (#26)

Answers the Codex checks in PRD §11. Run with codex-cli 0.166.0 on 5 November 2026. **All checks pass.**

| Check | Answer |
|-------|--------|
| `codex app-server` against a dedicated `CODEX_HOME` returns `usedPercent`, `windowDurationMins` and `resetsAt` via `account/rateLimits/read` | **Yes.** Signed in as a ChatGPT Team Account, it returned `primary: {usedPercent: 6, windowDurationMins: 300, resetsAt: 1793877447}` and `secondary: {usedPercent: 5, windowDurationMins: 10080, resetsAt: 1794386569}`, in both `rateLimits` and `rateLimitsByLimitId.codex`. `CodexUsageProvider` read them as `5h 6%` and `Weekly 5%` (`CODEX_PROBE_HOME=<folder> swift test --filter realServerSignedIn`). `codex app-server generate-json-schema` gives `GetAccountRateLimitsResponse.rateLimits` (and `rateLimitsByLimitId.codex`) with `primary` and `secondary` windows, each with `usedPercent` (int, required), `windowDurationMins` (int or null) and `resetsAt` (Unix seconds or null), plus `planType`. Newline-delimited JSON-RPC over stdio works: `initialize`, `initialized`, then the call. In a signed-out home, the call fails with code `-32600` and *codex account authentication required to read rate limits*, which the app treats as `Sign in required`. |
| `codex login` works in that folder | **Yes.** `CODEX_HOME=<folder> codex login --device-auth` signed in, and `codex login status` in that folder says *Logged in using ChatGPT*. |
| Codex can keep its credentials in the Keychain | **Yes.** `cli_auth_credentials_store` accepts `file`, `keyring`, `auto` and `ephemeral`, and the app writes `cli_auth_credentials_store = "keyring"` to each home's `config.toml`. After signing in, the folder has no `auth.json`. The login is in a *Codex Auth* Keychain item with account `cli|<hash of the home's path>`, so each home gets its own item. |
| The Owner's `~/.codex` login is left untouched | **Yes.** The SHA-1 of `~/.codex/auth.json` was the same before and after every probe and test run. The app sets `CODEX_HOME` on every Codex process it starts, and the probe refuses to run against `~/.codex`. |
| How to read the Account email and plan (A3, A5) | `account/read` with `{"refreshToken": false}` returns `account: {type: "chatgpt", email, planType, workspaceName}` (e.g. `planType: "team"`, `workspaceName: "Percayso"`), or `account: null` when signed out. The workspace becomes the Account's organisation (A5). |

## Run it

```bash
H="$HOME/Library/Application Support/Agent Usage/codex-probe"
mkdir -p "$H" && printf 'cli_auth_credentials_store = "keyring"\n' > "$H/config.toml"
CODEX_HOME="$H" codex login --device-auth      # approve in the browser
prototypes/codex-usage/probe.py "$H"
CODEX_HOME="$H" codex logout && rm -rf "$H"    # afterwards
```

Pass looks like `account/read` with your email and plan, and `account/rateLimits/read` with
`primary.windowDurationMins: 300` and `secondary.windowDurationMins: 10080` (Plus), each with
`usedPercent` and `resetsAt`.
