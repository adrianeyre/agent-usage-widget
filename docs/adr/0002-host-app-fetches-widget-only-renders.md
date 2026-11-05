# The host app fetches usage; the widget only draws it

The widget extension runs in a sandbox and can't read the host app's Keychain items that hold each Account's Authorisation (see ADR-0003). Sharing them would need a keychain access group, and that needs a Team ID we don't have (ADR-0004). So the host app runs in the background as a menu-bar item that starts at login. It fetches usage for every Account and writes one snapshot per Account to a location the widget can read (see ADR-0004). The widget's TimelineProvider only reads those snapshots and works out the pace marker positions. It never makes network calls or touches credentials. This depends on the app being for personal use only, so the host app can run outside the sandbox.

## Considered Options

- **The widget fetches directly** (the original PRD design). Ruled out because the sandboxed extension can't reach the Accounts' Authorisations.

## Consequences

- If the host app isn't running, no new data arrives. The widgets keep moving their pace markers from the last snapshot and show the stale state after 30 minutes.
- Distributing it publicly later would mean revisiting this decision, because a sandboxed, notarised host app couldn't read Claude Code's credentials.
