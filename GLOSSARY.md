# Agent Usage

A macOS desktop widget that shows how much of each AI subscription limit has been used, and whether that rate is sustainable, for one or more Accounts across several Providers.

## Accounts

**Provider**:
The company whose subscription plan sets the usage limits (e.g. Anthropic, OpenAI, Google, xAI).
_Avoid_: Service, vendor, platform, AI

**Account**:
One set of usage limits at one Provider: a sign-in email together with the organisation or plan it uses. The same email can belong to more than one Account (e.g. a personal plan and a work Team plan).
_Avoid_: Profile, user, login, subscription

**Account name**:
The required, unique label the owner gives an Account (e.g. "Work"), shown as the Account's main identifier. Defaults to the Account's email.
_Avoid_: Nickname, alias, display name

**Account email**:
The email address an Account signs in with, shown alongside the Account name as secondary identification.

**Authorisation**:
The long-lived permission, approved by the owner through the Provider's own sign-in flow, that lets the widget read an Account's usage. Its lifetime depends on the Provider.

**Re-authorise**:
To grant an Account a fresh Authorisation, replacing the old one.
_Avoid_: Reconnect, log in again, refresh

**Provider home**:
A folder owned by the app that holds one Account's login for a Provider's own CLI (a Claude Code folder, a Codex home or a Gemini CLI home). The app only ever runs that CLI against its Account's folder.
_Avoid_: Profile, config dir

**Owner**:
The one person who uses the widget and owns all of its Accounts.
_Avoid_: User, customer

## Limits and pace

**Limit**:
One usage allowance a Provider sets on an Account, with a name, a Window and a reset time (e.g. Claude's Session limit).
_Avoid_: Quota, cap, allowance (as a noun for the whole thing)

**Session limit**:
Claude's Limit for a rolling 5-hour Window.
_Avoid_: 5h limit, hourly limit

**Weekly limit**:
Claude's Limit for a 7-day Window.

**Monthly credits**:
GitHub Copilot's Limit: the AI credits a plan includes each calendar month, in UTC, resetting on the 1st at 00:00 UTC.
_Avoid_: Premium requests (the name before June 2026), quota

**Window**:
The span of time a Limit covers, ending at its reset time.

**Pace marker**:
The point on a Limit's bar showing how much usage would have been reached by now if the allowance were spread evenly across the Window.
_Avoid_: Target line, expected line

**On pace / over pace**:
Whether an Account's usage of a Limit is at or below the Pace marker (on pace) or beyond it (over pace).
_Avoid_: Ahead, behind (ambiguous about direction)

**Snapshot**:
The most recent usage figures fetched for an Account, together with when they were fetched.
_Avoid_: Cache, reading

**Stale**:
Describes an Account whose Snapshot is more than 30 minutes old.
_Avoid_: Old, expired (expired is for Authorisations)
