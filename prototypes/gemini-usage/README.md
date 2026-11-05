# Prototype: Gemini CLI usage from a dedicated home (#36)

Run on 5 November 2026 with Gemini CLI 0.67.0 (`npm install -g @google/gemini-cli`).

**Result: Gemini CLI is deferred.** The Owner's Google account isn't allowed to sign in to Gemini CLI, so the Provider is skipped under PV1 ("A Provider the Owner doesn't subscribe to is skipped"). What was learned without signing in is recorded below for when it's picked up again.

| Check | Answer |
|-------|--------|
| Point Gemini CLI at a dedicated home | **Yes:** `GEMINI_CLI_HOME=<folder>`. Gemini CLI's `homedir()` returns it, and the config lives in `<folder>/.gemini/`. |
| Its Google sign-in works there | **Not run.** The Owner's account can't sign in to Gemini CLI. |
| Where the login is stored | **Watch out.** By default, it goes in the macOS Keychain as service `gemini-cli-oauth`, account `main-account`, a fixed item that **ignores `GEMINI_CLI_HOME`**. Every home would then share the Owner's everyday Gemini login, which breaks U6. With `GEMINI_FORCE_FILE_STORAGE=true`, it uses an encrypted file, `<folder>/.gemini/gemini-credentials.json`, separate for each home. The app must always set both variables. |
| `retrieveUserQuota` fields | From the source: `buckets[]`, each with `modelId`, `remainingFraction`, optional `remainingAmount`, and `resetTime`. It's called as `retrieveUserQuota({ project })` on the Code Assist server. |
| Reading quota without the app reading the token | **No CLI command for it.** `gemini --help` and `gemini models` don't print quota. `/stats` is interactive only. The options would be running Gemini CLI's own bundled code in a helper process (fragile, because chunk names change every release), or reading the token, which U6 forbids for a login the app doesn't own. |
| Whether the refresh token rotates | **Not run.** |
| Account email | Not run. Gemini CLI keeps `google_accounts.json` in the home's `.gemini/`. |
