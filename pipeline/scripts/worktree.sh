#!/usr/bin/env bash
# Create a worktree + branch for a feature and its run folder.
# Usage: pipeline/scripts/worktree.sh <slug>
# Prints the absolute worktree path on the last line.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
cd "$repo"
source pipeline/config.sh

slug="${1:?usage: worktree.sh <slug>}"
branch="${BRANCH_PREFIX}${slug}"
mkdir -p "$WORKTREE_ROOT"
wt="$(cd "$WORKTREE_ROOT" && pwd)/$slug"

if [[ -d "$wt" ]]; then
  echo "Worktree already exists: $wt" >&2
else
  git fetch --quiet origin "$BASE_BRANCH" 2>/dev/null || true
  base_ref="origin/$BASE_BRANCH"
  git rev-parse --verify --quiet "$base_ref" >/dev/null || base_ref="$BASE_BRANCH"
  git worktree add -b "$branch" "$wt" "$base_ref" >&2
fi

run="$wt/.pipeline/$slug"
mkdir -p "$run"
if [[ ! -f "$run/meta.env" ]]; then
  cat > "$run/meta.env" <<EOF
SLUG=$slug
WT=$wt
RUN=$run
BRANCH=$branch
BASE_SHA=$(git -C "$wt" rev-parse HEAD)
TESTS_SHA=
EOF
fi
echo "$wt"
