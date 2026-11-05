# Signed with a self-signed certificate, with no App Group

The owner has no paid Apple Developer Program membership, so the app can't use a Team ID, provisioning profiles or notarisation. Instead:

- **Signing:** both targets are signed with one self-signed code-signing certificate, created once in Keychain Access. CI imports it from two repo secrets (the `.p12` and its password). The signer stays the same across builds, so the Keychain doesn't prompt again for each Account's Authorisation after every update.
- **Data sharing:** there's no App Group, because App Group containers need a Team ID or a profile on macOS 15 and later. The host app writes each Account's snapshot into its own Application Support folder. The sandboxed widget reads it through a read-only `temporary-exception.files.home-relative-path.read-only` entitlement for that one path. Snapshots never contain an Authorisation.
- **Installing:** releases aren't notarised. `scripts/install.sh` downloads them with `gh release download`, which doesn't set the quarantine flag, checks the SHA-256 and installs to `/Applications`.

## Considered Options

- **Ad-hoc signing:** the signature changes with every build, which brings back Keychain prompts after each update. It may also break the widget.
- **Free Personal Team:** its apps reportedly stop launching after 7 days.
- **Paid Developer ID:** this is the supported route (App Group, notarisation, opening downloads normally). It's the upgrade path if the owner ever joins, and it would replace this ADR.

## Consequences

- Each of these is unverified until the first prototype confirms it: the self-signed widget loads, the sandbox exception can read the file, the host app can reload the widget's timelines, and updates don't bring back Keychain prompts.
- Opening a release downloaded through a browser will be blocked by Gatekeeper. That's expected.

## Implementation notes

- Xcode builds sign each target ad hoc (`CODE_SIGN_IDENTITY = -`). `scripts/sign.sh` then re-signs the widget extension and the host app with `codesign`, using each target's entitlements file. Xcode's manual signing doesn't need to accept a certificate that isn't from Apple.
- CI imports the `.p12` into a temporary keychain that isn't added to the search list. `codesign --keychain` points at it, and the keychain is deleted at the end of every run, even a failed one.
- The certificate doesn't need to be trusted to sign. `security find-identity` lists it as `CSSMERR_TP_NOT_TRUSTED`, but `codesign` signs with it and `codesign -dvv` shows `Authority=Agent Usage Self-Signed`.
- Locally, `scripts/create-certificate.sh` keeps the certificate in its own keychain (`agent-usage-signing.keychain-db`), with random passwords stored in the login keychain. On a managed Mac, the login keychain's password can differ from the login password, so signing from it can fail (`errSecInternalComponent`). `scripts/sign.sh` uses that keychain when it exists.
- No Team ID also means no App Intents: a configurable widget's Account picker doesn't work (#17), so the widgets are numbered instead (ADR-0009).
- Check 8 failed: a self-signed app's login-keychain items are tied to its exact build (`cdhash:` partition), so updates prompted anyway. Authorisations moved to private files (ADR-0010).
- The designated requirement is `identifier "com.adrianeyre.AgentUsage" and certificate leaf = H"<certificate hash>"`. Every build signed with the same certificate meets it, which is what should keep Keychain prompts away after updates (§11 check 8).
