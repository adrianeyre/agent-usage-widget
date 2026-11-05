---
status: superseded by ADR-0003
---

# Each Account borrows a separate Claude Code login

To support multiple Accounts, each Account points at its own Claude Code configuration directory (one per sign-in, selected via `CLAUDE_CONFIG_DIR`), and the widget reads the credentials Claude Code already stores for it. The widget never signs in itself or creates credentials of its own. Claude Code holds only one login per configuration directory, so this is the only way to reuse its credentials for more than one Account. It also avoids building an undocumented OAuth flow and keeping new secrets.

## Considered Options

- **Host app runs its own sign-in per Account** and stores tokens in its own Keychain items. This removes the dependency on Claude Code, but it means re-implementing an undocumented OAuth flow and holding new long-lived secrets. It's the fallback if borrowing logins proves unworkable.
- **One claude.ai browser session cookie per Account.** This is the most fragile option, and handling the cookies securely is awkward.

## Consequences

- The owner must sign in to Claude Code once for each Account, each in its own configuration directory, before adding that Account to the widget.
- If Claude Code changes where or how it stores credentials, every Account breaks at once.
