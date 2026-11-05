# How it works

Agent Usage is two processes that share a folder of files:

```
 Provider APIs / CLIs                    ~/Library/Application Support/Agent Usage/
 ┌──────────────┐  every 5 min   ┌───────────────┐  writes   ┌──────────────────────┐
 │ claude, codex│ ◀───────────── │  Host app     │ ────────▶ │ widget/  Snapshots   │
 │ GitHub API   │ ─────────────▶ │  (menu bar)   │           │ host/    Accounts,   │
 └──────────────┘   usage        └───────────────┘           │          tokens,     │
                                         │ reloads           │          CLI folders │
                                         ▼ timelines         └──────────┬───────────┘
                                 ┌───────────────┐   reads widget/ only │
                                 │ Widget        │ ◀────────────────────┘
                                 │ (sandboxed)   │  draws; no network, no credentials
                                 └───────────────┘
```

## The host app fetches; the widget only draws

- The **menu-bar host app** (not sandboxed) fetches usage for every Account every 5 minutes, and at once on **Refresh now** (R1). Each Account is fetched on its own, so one failing never affects another (A7). After each fetch it writes one Snapshot per Account and asks WidgetKit to reload the widgets (ADR-0002).
- The **widget extension** (sandboxed) only reads those Snapshots and draws them. It never touches credentials or the network. Its sandbox exception is read-only and covers just `Application Support/Agent Usage/widget/` (ADR-0004).
- Each widget timeline has an entry every 5 minutes, and the Pace marker is worked out afresh for each entry from the stored reset time, so it moves between fetches and while the figures are Stale (P5, R2).

## Where things are kept

| Path (under `~/Library/Application Support/Agent Usage/`) | What | Who reads it |
|---|---|---|
| `widget/` | The published Accounts and their latest Snapshots, in Manage Accounts order. No secrets. | Host app (writes), widget (reads) |
| `host/accounts.json` | The Accounts: name, Provider, email, organisation, entered expiry. | Host app |
| `host/authorisations/` | Copilot tokens, one private file each, mode 600 (ADR-0010). | Host app |
| The Claude Code and Codex folders | One per Account, holding that CLI's own login (ADR-0005, ADR-0011). | The CLI, started by the host app |

## Authorisations

- The app **never reads or refreshes a login it doesn't own** (Claude Code's, Codex's, Gemini CLI's, …), so it can't log those tools out.
- Claude and Codex logins live in the app's own folders, held by those CLIs. The app starts `claude` with `CLAUDE_CONFIG_DIR` and `codex` with `CODEX_HOME` set to the Account's folder, and removes `CLAUDE_CODE_OAUTH_TOKEN` and `ANTHROPIC_API_KEY` from their environment so nothing overrides the folder's login.
- Copilot tokens are kept in private files rather than the Keychain: a self-signed app's Keychain access is tied to its exact build, so every update would ask for the login password (ADR-0010).

## Refresh interval

The interval is 5 minutes. To change it (in seconds, minimum 30):

```bash
defaults write com.adrianeyre.AgentUsage RefreshInterval -int 120
```

There's no settings UI for it in v1 (§13).

## The code

| Path | What's in it |
|------|--------------|
| `AgentUsageCore/Sources/AgentUsageCore/` | Pace maths, colouring, display models and Snapshot files. Foundation only. |
| `AgentUsageCore/Sources/AgentUsageViews/` | The design system (`DesignSystem.swift`), the bar and the widget views, with previews of every state. |
| `AgentUsageCore/Sources/AgentUsageHostKit/` | Accounts, storage, Providers, the refresh loop and the host app's UI: the dropdown, Manage Accounts and the sheets. |
| `AgentUsageCore/Sources/AgentUsageScreenshots/` | Renders the docs' screenshots (see [Development](development.md#screenshots)). |
| `App/HostApp/` | The menu-bar host app target. |
| `App/Widget/` | The widget extension target: six numbered widgets and their timeline. |

The reasoning behind each decision is in the [ADRs](../adr/), and the requirements are in the [PRD](../product-requirements-document/agent-usage-widget.md).
