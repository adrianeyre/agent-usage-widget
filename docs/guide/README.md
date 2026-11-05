# The Agent Usage guide

How Agent Usage works, part by part. Start with [Installing](installing.md), then [Adding Accounts](adding-accounts.md).

| Guide | What it covers |
|-------|----------------|
| [Installing](installing.md) | Requirements, `scripts/install.sh`, updating, first launch and uninstalling. |
| [Adding and managing Accounts](adding-accounts.md) | Signing Claude, Codex and Copilot Accounts in, placing the numbered widgets, renaming, re-ordering, re-authorising and removing, and the menu-bar dropdown. |
| [Reading the widgets](reading-usage.md) | Bars, the Pace marker and its maths, the colours, and every state. |
| [Providers](providers.md) | Which Providers are supported, where each one's figures come from, and why others aren't. |
| [How it works](how-it-works.md) | The host app and the widget, where everything is kept, Authorisations, the refresh interval and the code. |
| [Design](design.md) | The design system: principles, tokens, colour roles, shared parts and accessibility. |
| [Screenshots](screenshots.md) | Every screenshot, light and dark. |
| [Developing](development.md) | Setup, every command, the project layout, Fixture Accounts and rendering the screenshots. |
| [CI, releases and the website](releasing.md) | The workflows, semantic-release, the signing secrets and GitHub Pages. |
| [Troubleshooting](troubleshooting.md) | Common problems, debugging on macOS, and the widget, signing and Provider gotchas. |

The vocabulary (Provider, Account, Limit, Authorisation, Pace marker, …) is defined in [GLOSSARY.md](../../GLOSSARY.md). The requirements are in the [PRD](../product-requirements-document/agent-usage-widget.md), and the decisions in the [ADRs](../adr/).

## Decisions

| ADR | Decision |
|-----|----------|
| [ADR-0001](../adr/0001-accounts-borrow-claude-code-logins.md) | *Superseded:* Accounts borrow Claude Code's logins |
| [ADR-0002](../adr/0002-host-app-fetches-widget-only-renders.md) | The host app fetches usage, and the widget only draws it |
| [ADR-0003](../adr/0003-one-year-setup-tokens-per-account.md) | *Superseded:* one-year setup tokens for each Claude Account |
| [ADR-0004](../adr/0004-free-signing-without-app-group.md) | Self-signed, no App Group, script install |
| [ADR-0005](../adr/0005-codex-accounts-use-dedicated-codex-homes.md) | Each Codex Account uses its own Codex home, owned by the app |
| [ADR-0006](../adr/0006-copilot-usage-from-the-internal-quota-endpoint.md) | Copilot usage comes from Copilot's internal quota endpoint |
| [ADR-0007](../adr/0007-gemini-cli-accounts-use-dedicated-gemini-homes.md) | *Deferred:* Gemini CLI Accounts use dedicated Gemini CLI homes |
| [ADR-0008](../adr/0008-claude-usage-from-the-status-line-feed.md) | *Superseded:* Claude usage from Claude Code's status line feed |
| [ADR-0011](../adr/0011-claude-accounts-use-dedicated-claude-code-folders.md) | Each Claude Account uses its own Claude Code folder, signed in from Agent Usage |
| [ADR-0009](../adr/0009-numbered-widgets-instead-of-an-account-picker.md) | Numbered widgets instead of an Edit Widget Account picker |
| [ADR-0010](../adr/0010-authorisations-in-private-files-not-the-keychain.md) | Authorisations are kept in private files, not the Keychain |
