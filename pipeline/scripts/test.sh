#!/usr/bin/env bash
# Run the project's tests inside a worktree.
# Usage: pipeline/scripts/test.sh <worktree> [spm|xcode|both|custom]
# Exit code = test result (0 = all green). Full log goes to <run>/test-<n>.log;
# the last 60 lines are printed.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
source "$here/config.sh"

wt="${1:?worktree}"; runner="${2:-$TEST_RUNNER}"
slug="$(basename "$wt")"; run="$wt/.pipeline/$slug"
n=$(ls "$run"/test-*.log 2>/dev/null | wc -l | tr -d ' '); log="$run/test-$((n+1)).log"
cd "$wt"

if [[ "$runner" == "auto" ]]; then
  if [[ -f Package.swift ]]; then runner=spm
  elif [[ -n "$XCODE_SCHEME" ]]; then runner=xcode
  elif [[ -n "$CUSTOM_TEST_CMD" ]]; then runner=custom
  else echo "No test runner detected; set TEST_RUNNER in pipeline/config.sh" >&2; exit 64; fi
fi

run_spm()   { swift test 2>&1; }
run_xcode() {
  [[ -n "$XCODE_SCHEME" ]] || { echo "XCODE_SCHEME not set" >&2; return 64; }
  local rc=0 dest
  IFS=';' read -ra dests <<< "$XCODE_DESTINATIONS"
  for dest in "${dests[@]}"; do
    echo "=== xcodebuild test -destination '$dest' ==="
    # shellcheck disable=SC2086
    xcodebuild test $XCODE_CONTAINER -scheme "$XCODE_SCHEME" -destination "$dest" \
      -quiet 2>&1 || rc=$?
  done
  return $rc
}
run_custom() { bash -c "$CUSTOM_TEST_CMD" 2>&1; }

rc=0
{
  case "$runner" in
    spm)    run_spm    || rc=$? ;;
    xcode)  run_xcode  || rc=$? ;;
    both)   run_spm    || rc=$?; run_xcode || rc=$? ;;
    custom) run_custom || rc=$? ;;
    *) echo "unknown runner $runner"; rc=64 ;;
  esac
  echo "=== exit $rc ==="
} > "$log" 2>&1

tail -n 60 "$log"
echo "(full log: $log)"
exit "$rc"
