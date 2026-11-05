# Troubleshooting

Things that cost time while building Agent Usage, and how to look inside it when
something's wrong. Each gotcha has a workaround, mostly in the scripts.

- [Debugging on macOS](#debugging-on-macos)
- [Widgets](#widgets)
- [Signing](#signing)
- [Providers](#providers)
- [Common problems](#common-problems)

## Common problems

| You see | Why, and what to do |
|---------|---------------------|
| **Sign in required** on one Account | Its Authorisation was refused (revoked, expired or signed out). Click **Re-authorise** in the menu or in Manage Accounts and sign in again as the same account. Other Accounts are unaffected (A7). |
| **Re-authorise by 12 Nov** | A Copilot token expires within 7 days. Make a new token and paste it in with **Re-authorise**. |
| Dimmed bars and a ⚠ **Updated 42m ago** | The figures are Stale: the last good fetch is over 30 minutes old, or a reset time has passed. Check the network, then **Refresh now** (⌘R). The Pace markers keep moving while Stale (R2). |
| **No Account 3** on a widget | The widget shows the Account at position 3 in Manage Accounts, and there are fewer than three. Add one, or move one up or down. |
| **Waiting for the first update** | The Account was just added. The first fetch starts at once; if it doesn't finish, see the error under **Usage** in Manage Accounts. |
| The gallery shows old widgets or names | See [the gallery caches widgets by build number](#widgets). Reinstall with `scripts/install.sh` or `scripts/dev-install.sh`. |
| A Gatekeeper warning | The app was downloaded with a browser. Install with `scripts/install.sh`, which uses `gh` and so never sets the quarantine flag. |
| `Couldn't find the claude CLI` / `codex CLI` | Install [Claude Code](https://code.claude.com) or the [Codex CLI](https://github.com/openai/codex). The app looks in the usual install locations and your `PATH`. |

## Debugging on macOS

- **Use `/usr/bin/log`.** Some shells define `log` as a function, which makes `log show` fail without any error. Useful filters:
  - `/usr/bin/log show --last 10m --style compact --predicate 'process == "AgentUsageWidget"'` for the widget
  - `… --predicate 'process == "chronod" AND eventMessage CONTAINS[c] "adrianeyre"'` for WidgetKit
  - `… --predicate 'process == "linkd"'` for App Intents
  - `… --predicate 'sender == "Sandbox"'` for sandbox denials
- **The widget reads only `Application Support/Agent Usage/widget/`.** The sandbox exception is read-only and covers just that folder (ADR-0004). Everything host-only, including `host/authorisations/` and the Claude Code and Codex folders, is outside it on purpose.


## Widgets

- **No Edit Widget Account picker without a Team ID.** A configurable widget (`AppIntentConfiguration`) relies on macOS's App Intents service. It refuses any extension with no Team ID (`linkd: Unable to get teamId`), and a self-signed certificate never has one. Even a certificate with an OU field shows `TeamIdentifier=not set`. The widget lists Accounts once and then does nothing when one is chosen. That's why the gallery offers numbered static widgets instead (ADR-0009). Right-clicking one shows **Edit "Agent Usage"**, and it does nothing; that's expected.
- **The gallery caches widgets by build number.** WidgetKit keys its list of an extension's widgets on `CFBundleVersion`. A rebuilt `0.0.0 (0)` keeps showing the old widgets and old names, and `chronod` asks for widget kinds that no longer exist (`No matching descriptor`). `scripts/dev-install.sh` stamps every build with a new number. Releases get the CI run number (B5).
- **Xcode registers every build it makes.** The copies in `build/DerivedData/…/Debug` and `…/Release` are registered with LaunchServices and PlugInKit as well, and the gallery may use a stale one. Check with `pluginkit -m -v -A -D -i com.adrianeyre.AgentUsage.Widget`. Only `/Applications` should be listed. `dev-install.sh` unregisters the others.
- **No interpolated `configurationDisplayName`.** `.configurationDisplayName("Account \(n)")` builds a formatted `LocalizedStringKey`, and the extension crashes with *Formatted text for `configurationDisplayName` is not supported*. Pass a plain `String`.
- **Changing a widget's kind orphans placed widgets.** Widgets already on the desktop keep the old kind. Remove them and add the new ones from the gallery (right-click the **desktop**, not a widget → **Edit Widgets…**).
- **Debug code lives in a dylib.** In a Debug build, the widget's code is in `AgentUsageWidget.debug.dylib`, not the main executable, so run `strings` on the dylib when checking which build is installed.

## Signing

- **The login keychain's password may not be your login password.** On a managed Mac, where IT or single sign-on sets the password, the login keychain often keeps an older one. `codesign` then fails with `errSecInternalComponent`, or asks for a password nobody knows. `scripts/create-certificate.sh` keeps the certificate in its own keychain, with random passwords stored in the login keychain, so signing never prompts.
- **bash 3.2 and empty arrays.** macOS's `/bin/bash` treats `"${array[@]}"` on an empty array as unbound under `set -u`. Use `${array[@]+"${array[@]}"}`.
- **Self-signed apps can't keep Keychain access across updates.** In the login keychain, an item is tied to a *partition*. Apple-signed apps get their Team ID; a self-signed app gets its exact code hash (`cdhash:`), which changes with every build. So each update asked for the login-keychain password before the Copilot token could be read, even with the same certificate. The Data Protection keychain needs a Team ID (`-34018`). Tokens are now kept in private files instead (ADR-0010).
- **Keep the same certificate anyway.** The designated requirement (`certificate leaf = H"…"`) still identifies the app to macOS, e.g. for Open at login and the widget's registration.

## Providers

- **Claude setup tokens can't read usage.** `claude setup-token` tokens lack the `user:profile` scope, so `/api/oauth/usage` and `/api/oauth/profile` both return 403. The API's rate-limit headers aren't sent to them either (#16). The only documented source is the status line's `rate_limits` (ADR-0008). It exists only for Pro, Max and Ultra plans, and only after Claude Code's first API response in a session.
- **Claude's `/usage` works headless, for free.** `claude -p /usage --output-format json` is a local command: `num_turns` 0, `total_cost_usd` 0. Its figures are in the human-readable `result` text, so the parser must be forgiving. A signed-out folder prints a cost summary instead, so check `claude auth status --json` (`loggedIn`).
- **`claude auth login` finishes by itself if the browser is already signed in.** That's handy, but it also means it signs in as whoever the browser is signed in as. For a second account, sign out of claude.ai first or use a private window. Each `CLAUDE_CONFIG_DIR` gets its own Keychain item, `Claude Code-credentials-<hash>`, and `claude auth logout` deletes it.
- **Don't let Claude Code inherit a token.** `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` in the environment would override the folder's login. The app removes them from every Claude Code process it starts.
- **Codex: never share a login.** ChatGPT refresh tokens rotate, so the app only ever runs Codex with `CODEX_HOME` set to the Account's own folder. With `cli_auth_credentials_store = "keyring"`, the folder has no `auth.json`. The login is a *Codex Auth* Keychain item keyed on the folder's path. `codex login --device-auth` works in a terminal. The app runs `codex login`, which opens the browser.
- **Copilot's documented billing API has no allowance.** `…/settings/billing/ai_credit/usage` reports what was used, but not the monthly allowance, so it can't give a percentage. The app reads `copilot_internal/user` instead, which is undocumented and fragile (ADR-0006).
- **Copilot's expiry header needs an expiring token.** `github-authentication-token-expiration` (e.g. `2027-11-05 00:00:00 UTC`) is only sent for tokens that expire. A *No expiration* token sends none, so enter the expiry when adding the Account. *Plan: read* can't read `/user/emails` (403), so the Account shows `@username` plus your public profile email.
- **Gemini CLI's Keychain item ignores its home.** `GEMINI_CLI_HOME` moves the config, but the default login storage is one fixed Keychain item (`gemini-cli-oauth` / `main-account`). Set `GEMINI_FORCE_FILE_STORAGE=true` as well, or every home shares your everyday login.
- **Copilot Free has no credits.** Its `premium_interactions` entitlement is 0, so a Free Account shows its monthly Chat and Completions allowances instead.

