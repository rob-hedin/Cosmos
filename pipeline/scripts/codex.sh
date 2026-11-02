#!/usr/bin/env bash
# Run one Codex step non-interactively inside a feature worktree.
# Usage: pipeline/scripts/codex.sh <plan-review|tests|code-review> <worktree> <round>
# Writes  <run>/<role>-r<round>.md  (Codex's final message) and a .log next to it.
# Prints the VERDICT line (reviews) or DONE (tests). Exit 2 if no verdict found.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
source "$here/config.sh"

role="${1:?role}"; wt="${2:?worktree}"; round="${3:?round}"
slug="$(basename "$wt")"
source "$wt/.pipeline/$slug/meta.env"

case "$role" in
  plan-review) model=$CODEX_PLAN_REVIEW_MODEL; effort=$CODEX_PLAN_REVIEW_EFFORT; sandbox=read-only ;;
  tests)       model=$CODEX_TESTS_MODEL;       effort=$CODEX_TESTS_EFFORT;       sandbox=workspace-write ;;
  code-review) model=$CODEX_CODE_REVIEW_MODEL; effort=$CODEX_CODE_REVIEW_EFFORT; sandbox=read-only ;;
  *) echo "unknown role: $role" >&2; exit 64 ;;
esac

out="$RUN/$role-r$round.md"
prompt="$RUN/$role-r$round.prompt.md"
prev="$RUN/$role-r$((round-1)).md"

# Fill the template placeholders.
sed -e "s|{{RUN}}|.pipeline/$SLUG|g" \
    -e "s|{{BASE_SHA}}|$BASE_SHA|g" \
    -e "s|{{TESTS_SHA}}|${TESTS_SHA:-}|g" \
    -e "s|{{ROUND}}|$round|g" \
    -e "s|{{MAX_ROUNDS}}|$MAX_ROUNDS|g" \
    "$here/prompts/$role.md" > "$prompt"
if [[ -f "$prev" ]]; then
  printf '\n\nYour previous round output is in `.pipeline/%s/%s`. Check whether each point was addressed.\n' \
    "$SLUG" "$(basename "$prev")" >> "$prompt"
fi

codex exec \
  -m "$model" \
  -c "model_reasoning_effort=\"$effort\"" \
  -c 'approval_policy="never"' \
  -s "$sandbox" \
  -C "$wt" \
  --output-last-message "$out" \
  - < "$prompt" > "${out%.md}.log" 2>&1 || { echo "codex exited with error, see ${out%.md}.log" >&2; exit 1; }

if [[ "$role" == "tests" ]]; then
  echo "DONE $out"
else
  grep -m1 -E '^VERDICT: (APPROVE|REVISE)' "$out" || { echo "NO VERDICT in $out" >&2; exit 2; }
fi
