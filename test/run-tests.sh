#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

run_test() {
  local test_name="$1"
  if "$test_name"; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$test_name"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  ✗ ${test_name}"
    printf "  ✗ %s\n" "$test_name"
  fi
}

run_suite() {
  local suite="$1"
  printf "\n%s\n" "$suite"
  source "$suite"
  for fn in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$fn"
    unset -f "$fn"
  done
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
for suite in "$SCRIPT_DIR"/test-*.sh; do
  run_suite "$suite"
done

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf "\nFailures:%b\n" "$ERRORS"
  exit 1
fi
