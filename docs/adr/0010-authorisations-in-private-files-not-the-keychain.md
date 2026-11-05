# Authorisations are kept in private files, not the Keychain

ADR-0004 expected that signing every build with the same certificate would keep Keychain prompts away after updates (§11 check 8). The #17 prototype showed it doesn't. In the login (file-based) keychain, an item's access is tied to a *partition* for the program that created it. Apple-issued signatures get `teamid:<Team ID>`, but a self-signed app gets `cdhash:<code hash>`, and that changes with every build. After each update, macOS asked for the login-keychain password before the app could read a Copilot token. On the Owner's managed Mac, nobody knows that password. The Data Protection keychain (`kSecUseDataProtectionKeychain`) would avoid partitions, but it needs an entitlement backed by a Team ID: a self-signed test returned `-34018` *A required entitlement is not present*.

So each Authorisation is kept in its own file, `~/Library/Application Support/Agent Usage/host/authorisations/<account-id>`. The folder is mode 700 and the file is mode 600. Writes are atomic, and Re-authorise replaces the file rather than adding a second one. The widget's read-only sandbox exception covers only `widget/`, so the widget can't read these files.

Today the only Authorisation stored is a **Copilot** fine-grained token with *Plan: read* only. Claude stores nothing (ADR-0008), and Codex keeps its own login in a Keychain item owned by the `codex` binary, which is Developer ID signed (ADR-0005).

## Considered Options

- **Keep the login Keychain** and accept a password prompt after every update. Rejected: on this Mac, the prompt can't be answered.
- **An app-owned keychain file** whose password the app keeps in a 600 file, re-granting itself access after each update. Rejected: the key would sit next to the lock, so it's no safer than a private file, and it's more complex.
- **A paid Developer ID** would give a `teamid:` partition and allow the Data Protection keychain (ADR-0004's upgrade path). It would replace this ADR.

## Consequences

- No prompts after updates. Check 8 passed on build 202611051225.
- Any program running as the Owner can read the file. That's accepted because the token can only read the plan's usage. FileVault protects it at rest.
- PRD §7.3's "never written to disk in plain text" is relaxed to "never written anywhere but the Account's private file".
- An Account added before this change has its token in the login Keychain, and the app no longer reads it there, so it shows `Sign in required` until it's Re-authorised once. The old item, `com.adrianeyre.AgentUsage.authorisation`, can be deleted in Keychain Access.
