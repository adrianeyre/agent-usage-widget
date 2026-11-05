---
status: superseded by ADR-0008
---

# Each Claude Account is authorised with a one-year Claude Code setup token

Each Account's Authorisation is a token created by `claude setup-token`, which Claude Code documents as a one-year OAuth token. **Re-authorise** runs that command, the owner approves it in the browser, and the host app captures the printed token. It then stores the token in its own Keychain item for that Account, along with the date it was created. Expiry is assumed to be one year after creation, so the 7-day warning to re-authorise counts down from that date.

This replaces ADR-0001 (borrowing each Account's normal Claude Code login). A normal login's access token lasts only about 8 hours. Renewing it replaces the refresh token, so if the app refreshed it, Claude Code's own copy could be logged out (see anthropics/claude-code#54443). Borrowing read-only would leave an Account's data frozen once a few hours had passed without Claude Code being used.

**Hard rule:** the app never reads, refreshes or rewrites a normal Claude Code login.

## Consequences

- The app now holds a long-lived secret for each Account. Removing an Account deletes its Keychain item.
- Claude Code says setup tokens are for model requests only, and it doesn't document whether they can read usage data. This must be checked with a prototype before anything else is built.
- Claude Code config directories are no longer involved.
