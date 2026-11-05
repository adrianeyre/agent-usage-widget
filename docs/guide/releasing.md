# CI, releases and the website

## Workflows

| Workflow | Runs on | What it does |
|----------|---------|--------------|
| **CI** (`ci.yml`) | Every pull request | `scripts/test.sh` on `macos-26` (unit tests, Debug and Release builds, the Release check). When the signing secrets exist, also signs a Release build and uploads it as an artifact for 14 days. A second job type-checks and builds the website. |
| **Commit messages** (`commitlint.yml`) | Every pull request | Lints every commit in the pull request against Conventional Commits. |
| **Release** (`release.yml`) | Every push to `main` | Builds and tests, then semantic-release picks the version from the commits, updates `CHANGELOG.md`, tags the commit and publishes a signed, checksummed release. |
| **Pages** (`pages.yml`) | Pushes to `main` that change the website, the screenshots or its packages; or by hand | Builds `site/` and deploys it to GitHub Pages. |

Any of them can also be started by hand: **Actions → Run workflow**, or `gh workflow run <file>`.

## Releases

On every push to `main`, semantic-release reads the Conventional Commits since the last tag (`v<version>`):

- `fix:` → patch, `feat:` → minor, `BREAKING CHANGE` / `feat!:` → major; other types make no release.
- Its prepare step runs `scripts/build-release.sh <version>`, which builds with `MARKETING_VERSION=<version>` and `CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER` (B5), signs both targets and writes `dist/AgentUsage-<version>.zip` and its `.sha256`.
- `@semantic-release/changelog` prepends the release notes to `CHANGELOG.md`, and `@semantic-release/git` commits it to `main` as `chore(release): <version> [skip ci]`.
- That commit is tagged `v<version>`, and the GitHub release is created from the tag, with the zip, its `.sha256` and the same notes.

The `main` ruleset blocks only deletion and force-pushes, so the workflow's `GITHUB_TOKEN` (with `contents: write`) can push the release commit. If you later make the ruleset require pull requests or status checks, add a bypass for the release (for example a GitHub App or deploy key that the workflow pushes with), or the release fails at the push.

Install a release with `scripts/install.sh` ([Installing](installing.md)).

## Signing secrets

CI signs both targets with the `Agent Usage Self-Signed` certificate (ADR-0004). It reads two repo secrets:

| Secret | Value |
|--------|-------|
| `SIGNING_CERTIFICATE_P12_BASE64` | The exported `.p12`, base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
| `SIGNING_CERTIFICATE_PASSWORD` | The `.p12`'s password |

Pull-request builds skip signing when the secrets are missing. Releases fail without them.

`scripts/create-certificate.sh --update-secrets` makes a new certificate and sets both secrets. `--secrets-only` sets them from the existing certificate. Keep the backup `.p12` it writes to `~/Library/Application Support/Agent Usage Signing/`: if the certificate is lost, every Mac has to switch to a new signer.

## The website

The project website, [adrianeyre.github.io/agent-usage-widget](https://adrianeyre.github.io/agent-usage-widget/), is a static page in `site/` with product demos built in React on the vendored [Stageshow](https://github.com/benjitaylor/skills) kit (`site/stageshow/`).

- `pnpm site:build` assembles it in `site/dist/`, copying the screenshots in from `docs/images/` so they're never kept twice.
- The **Pages** workflow builds it on `ubuntu-latest` and deploys it with `actions/deploy-pages`. Only the deploy job holds the Pages scopes.
- In **Settings → Pages**, the source must be **GitHub Actions**.

## Repo name

This repo, `adrianeyre/agent-usage-widget`, took over from `adrianeyre/claude-usage-indicator`, where Agent Usage was developed. `AGENT_USAGE_REPO`'s default in `scripts/install.sh`, the website's repository URL in `site/build.ts` and the Pages address all point here.
