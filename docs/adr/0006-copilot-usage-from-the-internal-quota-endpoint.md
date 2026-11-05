# Copilot usage comes from Copilot's internal quota endpoint

GitHub's documented billing API (`/users/{username}/settings/billing/ai_credit/usage` and its siblings) reports how many credits were used and what they cost, but not the plan's monthly allowance. So it can't give a percentage of **Monthly credits** without the Owner typing in the allowance, and that would break R6. The app reads `GET https://api.github.com/copilot_internal/user` instead. This is the endpoint Copilot's editor extensions use. It returns `quota_snapshots`, and each snapshot has `entitlement`, `remaining`, `percent_remaining` and `unlimited`. It also returns `quota_reset_date_utc`. The Authorisation is still a fine-grained personal access token in the app's Keychain, with the *Plan: read* permission and the longest expiry GitHub allows (U1). Its expiry comes from the `github-authentication-token-expiration` header (U3).

The Limit is **Monthly credits** (`premium_interactions`). Its Window is the UTC calendar month that ends at `quota_reset_date_utc`. Copilot Free has no credits, so Free Accounts show its monthly `Chat` and `Completions` allowances instead. Unlimited buckets aren't shown.

## Considered Options

- **The documented billing API, with the allowance typed in:** stable, but the percentage would rest on a number the Owner entered, and it would go wrong without warning whenever GitHub changes a plan.
- **Skipping Copilot:** the Owner chose to keep it.

## Consequences

- PV3 allows this source because the figures are real, but it's **fragile**: the endpoint is undocumented and GitHub can change or remove it without notice. When that happens, the Copilot Provider reports an unexpected response and shows no figures (R6), and the other Providers carry on (A7).
- A fine-grained token with only *Plan: read* is enough (#27). GitHub sends `github-authentication-token-expiration` only for tokens that expire. For a *No expiration* token, the Owner can enter an expiry when adding or re-authorising, and the header wins whenever it's sent.
- 401, 403 and 404 all mean `Sign in required`, because a token without the right permission, or a plan without Copilot, gets 403 or 404.
