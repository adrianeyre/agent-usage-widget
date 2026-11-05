#!/usr/bin/env bash
# Renders the README's and the website's screenshots from the app's real SwiftUI views,
# with sample Accounts only, into docs/images/ (or the folder given). The site build
# copies docs/images/ in, so they're never kept twice. Needs a Mac with Xcode 26+.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-docs/images}"
# Debug, so the renderer can reach the host app's internal sheets (@testable).
swift run --package-path AgentUsageCore -c debug AgentUsageScreenshots "$PWD/$OUT"
