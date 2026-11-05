# Prototype: self-signed widget, sandbox read and timeline reload (#17)

Answers PRD §11 checks 5–8 on the Owner's Mac (macOS 27.0, 5 November 2026), signed with
the `Agent Usage Self-Signed` certificate.

| Check | Answer |
|-------|--------|
| 5. The self-signed widget is in the gallery and runs | **Yes.** PlugInKit registers `com.adrianeyre.AgentUsage.Widget`, and the gallery lists the widgets, which draw sample bars. |
| 6. The read-only sandbox exception reads the Snapshot | **Yes.** The sandboxed widget reads `widget/index.json` and `widget/accounts/<id>.json`. "Agent Usage: Account 1" and "Account 2" showed the Owner's real Claude and Codex Accounts. |
| 7. The host app reloads the widget's timelines | **Yes.** Moving Codex up in Manage Accounts swapped the two widgets within seconds. |
| 8. A new build with the same certificate brings back no Keychain prompts | See the #17 issue comment. |

**What failed, and the re-grill:** the planned **Edit Widget** Account picker (`AppIntentConfiguration`) can't work with a self-signed build. `linkd` logs *Unable to get teamId*, and the picker never takes effect. The Owner chose numbered widgets instead (ADR-0009).

## Build a signed copy

```bash
scripts/create-certificate.sh   # once per Mac
scripts/dev-install.sh          # build, sign, install to /Applications, refresh WidgetKit
```

See the README's **Gotchas** section for the widget caching traps found along the way (the build number, the build-folder copies Xcode registers, and the formatted display name).

Useful when something fails:

```bash
codesign -dvv --entitlements - "/Applications/Agent Usage.app/Contents/PlugIns/AgentUsageWidget.appex"
pluginkit -m -v -A -D -i com.adrianeyre.AgentUsage.Widget
ls -la ~/Library/Application\ Support/Agent\ Usage/widget/accounts/
/usr/bin/log show --last 10m --style compact --predicate 'process == "AgentUsageWidget" OR process == "linkd"'
```
