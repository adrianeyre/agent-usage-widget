# Prototype: Copilot usage (#27)

Answers the Copilot checks in PRD §11. Run on 5 November 2026: first with the Owner's `gh`
OAuth login, then with a classic token, and finally with fine-grained tokens that have only
*Plan: read*. **All checks are answered.**

| Check | Answer |
|-------|--------|
| The billing endpoint still reports usage since the switch to credits | **Not enough for a percentage.** `GET /users/{u}/settings/billing/ai_credit/usage` (and `…/usage`, `…/usage/summary`, `…/premium_request/usage`) report quantities and amounts, but no field gives the monthly allowance. With the `gh` token they answer 404 and ask for the `user` scope. The docs disagree on whether fine-grained tokens are accepted. |
| Where a percentage can be read | `GET https://api.github.com/copilot_internal/user`, the endpoint Copilot's editor extensions use. It returns `quota_snapshots.{premium_interactions,chat,completions}`, each with `entitlement`, `remaining`, `percent_remaining`, `credits_used` and `unlimited`, plus `quota_reset_date_utc` (the 1st of next month, 00:00 UTC). It's undocumented: see ADR-0006. |
| *Plan: read* is enough | **Yes.** A fine-grained token with *Plan: read* only (public repositories read-only, nothing else) gets HTTP 200 from `copilot_internal/user` with the full `quota_snapshots`. The official `…/billing/ai_credit/usage` report also answers 200 (`x-accepted-github-permissions: plan=read`), but its `usageItems` is empty. |
| `github-authentication-token-expiration` is present | **Yes, when the token has an expiry.** A token that expires on 5 November 2027 sends `github-authentication-token-expiration: 2027-11-05 00:00:00 UTC` on every response. A *No expiration* token sends no header. For that case, Add Account and Re-authorise ask for the expiry (or *no expiry*), and the header wins whenever it's sent (U3). |
| Username, and email if allowed (PV6) | `GET /user` gives `login`, `id` and the public profile `email`. `GET /user/emails` answers 403 (*Resource not accessible by personal access token*, needs `emails=read`), so the Account email is `@username`, plus the public profile email when there is one. |

The Owner's account is on **Copilot Free** (`access_type_sku: free_limited_copilot`), which
has no credits allowance (`premium_interactions.entitlement` is 0), but does have monthly
`chat` (200) and `completions` (2000) allowances. The Provider shows **Monthly credits**
when the plan has them, and otherwise the Free plan's `Chat` and `Completions` Limits.

## Run it

Create a fine-grained token at <https://github.com/settings/personal-access-tokens/new> with
no repository access, the account permission **Plan: read** only, and the longest expiry
allowed. Then:

```bash
prototypes/copilot-usage/probe.sh
```

If `copilot_internal/user` refuses the token (401, 403 or 404), the Provider can't work with a
*Plan: read* token: grill again before relying on it.
