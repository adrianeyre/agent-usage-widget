# Installing Agent Usage

## Requirements

- **macOS 27.0.1** (the deployment target is macOS 26).
- A **subscription plan** for each Account, e.g. Claude Pro, Max or Ultra; a ChatGPT plan for Codex; any Copilot plan, including Copilot Free.
- **Each Provider's own CLI**, where it has one:
  - Claude needs [Claude Code](https://code.claude.com) installed.
  - Codex needs the [Codex CLI](https://github.com/openai/codex).
  - Copilot needs only a GitHub token.
- The [GitHub CLI](https://cli.github.com) (`gh`), signed in with access to this private repository, to download releases.

## Install

Releases are self-signed and not notarised (ADR-0004), so install them with the script. A release downloaded through a browser is quarantined, and Gatekeeper blocks it.

```bash
scripts/install.sh            # the latest release
scripts/install.sh 1.2.0      # a specific version
```

The script:

1. downloads `AgentUsage-<version>.zip` and its `.sha256` with `gh release download` (which never sets the quarantine flag),
2. checks the SHA-256,
3. quits the running app, replaces `/Applications/Agent Usage.app` and relaunches it.

Run the same command to update. It's safe to run again at any time.

| Variable | What it changes |
|----------|-----------------|
| `AGENT_USAGE_REPO` | The `owner/repo` to download from (default `adrianeyre/agent-usage-widget`). |
| `AGENT_USAGE_INSTALL_DIR` | Where to install (default `/Applications`). |
| `AGENT_USAGE_ASSETS_DIR` | Install from already-downloaded assets in this folder instead of `gh` (for testing). |
| `AGENT_USAGE_NO_LAUNCH=1` | Don't quit or relaunch the app (for testing). |

## First launch

Agent Usage is a **menu-bar app**: look for the **gauge** icon at the right of the menu bar. It has no Dock icon and no main window.

- **Open at login** is on by default. Turn it off at the foot of **Manage Accounts…**.
- With no Accounts yet, the dropdown says so and offers **Add Account…**. Continue with [Adding Accounts](adding-accounts.md).

## Uninstall

1. Choose **Quit Agent Usage** (⌘Q) in the dropdown.
2. Remove any Agent Usage widgets from the desktop.
3. Delete `/Applications/Agent Usage.app`.
4. Optionally delete `~/Library/Application Support/Agent Usage/`, which holds the Accounts, their published Snapshots, the Copilot tokens and the app's own Claude Code and Codex folders. Your everyday `~/.claude` and `~/.codex` are never touched.
