---
status: deferred: the Owner's account can't sign in to Gemini CLI (#36)
---

# Each Gemini CLI Account uses its own Gemini CLI home, owned by the app

The Owner uses Gemini CLI through a **Google AI Pro** subscription. Gemini CLI keeps a Google OAuth login, so the app follows the Codex pattern (ADR-0005). Each Gemini Account gets a **dedicated Gemini CLI home owned by the app** (`~/Library/Application Support/Agent Usage/gemini/<account-id>/`). **Re-authorise** runs Gemini CLI's own Google sign-in there. Gemini CLI refreshes its own tokens, and nothing else uses that folder, so even if Google rotates the refresh token, nothing clashes (U6). The Owner's everyday Gemini CLI login is never used.

Usage comes from the internal Code Assist `retrieveUserQuota` method, the one Gemini CLI's `/stats` uses. It returns a bucket for each model, each with a remaining fraction and a reset time. The app shows two Limits, **Pro daily** and **Flash daily**. Each has a 24-hour Window that ends at its bucket's reset time, and `% used = (1 − remainingFraction) × 100`. Per-minute caps aren't shown.

## Considered Options

- **The app runs its own Google OAuth** with Gemini CLI's public client ID and keeps the refresh token in its Keychain. Rejected: it means more code, it borrows another app's client ID, and the app would have to handle rotation itself.
- **Showing only the most-used bucket:** rejected in favour of one bar each for Pro and Flash.

## Consequences

- The source is undocumented, so PV3 allows it only with this ADR's warning that it's fragile.
- Gemini CLI must be installed, and the prototype has to show that it can be pointed at another home (an environment variable such as `GEMINI_CLI_HOME`, or `HOME`), and how to call `retrieveUserQuota` with that home's login without the app reading the token itself.
- In June 2026, Antigravity CLI replaced Gemini CLI for unpaid and Google One users. If AI Pro moves too, revisit this ADR.

## Prototype findings (#36)

- `GEMINI_CLI_HOME` moves Gemini CLI's home, but its default login storage is a single Keychain item (`gemini-cli-oauth` / `main-account`) shared by every home. `GEMINI_FORCE_FILE_STORAGE=true` is required, so each home keeps its own `.gemini/gemini-credentials.json`.
- No command prints the quota, so reading `retrieveUserQuota` would mean running Gemini CLI's own code in a helper process.
- The Owner's Google account isn't allowed to sign in to Gemini CLI, so the Provider is deferred under PV1. Reopen #35 if that changes.
