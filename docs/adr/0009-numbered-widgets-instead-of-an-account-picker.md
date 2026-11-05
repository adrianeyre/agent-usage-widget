# Numbered widgets instead of an Edit Widget Account picker

PRD §6.1 had each widget choose its Account under **Edit Widget**, through an `AppIntentConfiguration` with an `AccountEntity` picker. The #17 prototype showed this can't work with a self-signed build. macOS's App Intents service (`linkd`) refuses an extension with no Team ID: it logs *Failed to generate bundleIdentity: Unable to get teamId*, and the widget logs *… is not a registered AppEntity identifier*. The picker listed one Account, and choosing it drew nothing. `codesign` only gets a Team ID from an Apple-issued certificate. Even a self-signed certificate with an OU shows `TeamIdentifier=not set`.

So the widget extension offers six **static** widgets, **Agent Usage: Account 1** to **Account 6**. Each one shows the Account at that position in Manage Accounts (`PublishedStore.account(atSlot:)`). Manage Accounts shows each Account's number, and **Move Up** / **Move Down** (or dragging) decides which widget shows which Account. A widget whose position has no Account shows `No Account <n>`. It never falls back to another Account.

## Considered Options

- **A paid Developer ID** (ADR-0004's upgrade path) gives a Team ID, so the picker works. Not chosen: it costs money and replaces the whole signing approach.
- **The deprecated SiriKit `.intentdefinition` configuration:** unproven, and likely blocked by the same Team ID check.

## Consequences

- At most six Accounts can have a widget. Accounts beyond six are listed with `–` and appear only in the menu.
- Re-ordering Accounts moves them between widgets. This is the intended way to choose what a widget shows.
- Widgets placed before this change have the old kind (`AccountUsage`) and must be removed and added again.
- If the app ever moves to a Developer ID, the picker can come back. That would replace this ADR.
