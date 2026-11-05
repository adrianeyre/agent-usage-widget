# Each Codex Account uses its own Codex home, owned by the app

The app reads Codex usage by starting `codex app-server` for each fetch and calling `account/rateLimits/read`. ChatGPT's OAuth refresh tokens rotate when they're used, so two programs sharing one Codex login can log each other out. To avoid that, each Codex Account gets a **dedicated Codex home folder owned by the app** (`~/Library/Application Support/Agent Usage/codex/<account-id>/`). The app only ever runs Codex with `CODEX_HOME` set to that folder. **Re-authorise** runs `codex login` there. Codex refreshes its own tokens, and because it's the only program using that folder, nothing clashes. Codex can keep its credentials in the Keychain rather than `auth.json` (`cli_auth_credentials_store = "keyring"`, checked in #26), so the app writes that to each home's `config.toml`.

Unlike Claude (ADR-0003), the Authorisation is held by Codex inside storage the app owns, rather than by the app itself. U6 therefore reads "Authorisations live only in storage the app owns". The owner's everyday `~/.codex` login is never used.

## Considered Options

- **Borrowing the owner's `~/.codex` login:** rejected. The refresh tokens rotate, so Codex and the app would end up logging each other out.
- **The app refreshing ChatGPT tokens itself:** rejected for the same reason, and it would also mean re-implementing ChatGPT OAuth.
- **The unofficial `chatgpt.com/backend-api/wham/usage` endpoint:** rejected in favour of `app-server`, which is in OpenAI's own repo.

## Consequences

- The `codex` CLI must be installed. Each Codex Account needs one extra sign-in, separate from the owner's everyday Codex login.
- A ChatGPT login has no known expiry, so Codex Accounts show no `Re-authorise by` warning, only `Sign in required` when authentication fails.
- `app-server`'s usage schema is marked unstable, so a Codex update could break the fetch.

## Implementation notes (#26)

- Each fetch starts `codex app-server` over stdio with `CODEX_HOME` set, sends `initialize` and `initialized`, then calls `account/rateLimits/read`. It reads `rateLimitsByLimitId.codex`, falling back to `rateLimits`. The `primary` and `secondary` windows each give `usedPercent`, `windowDurationMins` and `resetsAt` (Unix seconds). Limits are named from their window length (`5h`, `Weekly`) and shown shortest first.
- A signed-out home answers JSON-RPC error `-32600` (*codex account authentication required…*), which means `Sign in required`.
- `account/read` with `refreshToken: false` gives the email, `planType` and `workspaceName`. The plan or workspace stands in for the organisation when looking for duplicates (A5).
- Removing an Account runs `account/logout` in its home, which also deletes the Keychain item, and then deletes the folder (A6).
- The field names come from `codex app-server generate-json-schema` (codex-cli 0.166.0).
