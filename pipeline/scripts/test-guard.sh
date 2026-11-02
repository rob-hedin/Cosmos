#!/usr/bin/env bash
# Freeze tests after the red phase, and verify nobody changed them afterwards.
# Usage:
#   pipeline/scripts/test-guard.sh record <worktree>   # commit tests, store TESTS_SHA
#   pipeline/scripts/test-guard.sh check  <worktree>   # exit 1 if test files changed
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
source "$here/config.sh"

cmd="${1:?record|check}"; wt="${2:?worktree}"
slug="$(basename "$wt")"; meta="$wt/.pipeline/$slug/meta.env"
source "$meta"
cd "$wt"

case "$cmd" in
  record)
    for ps in "${TEST_PATHSPECS[@]}"; do git add -A -- "$ps" 2>/dev/null || true; done
    # Xcode projects without synchronized folders need pbxproj changes for new test files.
    git add -- ':(glob)**/project.pbxproj' 2>/dev/null || true
    other=$(git status --porcelain | grep -v '^A \|^M ' | grep -v '.pipeline/' || true)
    if [[ -n "$other" ]]; then
      echo "Non-test changes present (tests step must only add tests):" >&2
      echo "$other" >&2
      exit 1
    fi
    git commit -q -m "test($SLUG): add failing tests (red)"
    sha=$(git rev-parse HEAD)
    sed -i.bak "s/^TESTS_SHA=.*/TESTS_SHA=$sha/" "$meta" && rm -f "$meta.bak"
    echo "TESTS_SHA=$sha"
    ;;
  check)
    [[ -n "${TESTS_SHA:-}" ]] || { echo "TESTS_SHA not recorded" >&2; exit 1; }
    changed=$(git diff --name-only "$TESTS_SHA" -- "${TEST_PATHSPECS[@]}"; \
              git ls-files --others --exclude-standard -- "${TEST_PATHSPECS[@]}")
    if [[ -n "$changed" ]]; then
      echo "FROZEN TESTS CHANGED:" >&2; echo "$changed" >&2; exit 1
    fi
    echo "tests unchanged since $TESTS_SHA"
    ;;
esac
