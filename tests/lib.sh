# Shared test helpers. Sourced by every *.test.sh file.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_ROOT="$REPO_ROOT/skills/bq-pm-quant"
BIN="$SKILL_ROOT/scripts"
export REPO_ROOT SKILL_ROOT BIN

TESTS_RUN=0
TESTS_FAILED=0

pass() { TESTS_RUN=$((TESTS_RUN + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  FAIL %s\n' "$1"
  [[ $# -gt 1 ]] && printf '       %s\n' "$2"
  return 0
}

assert_ok() {   # assert_ok <name> <command...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name" "command failed: $*"; fi
}

assert_fails() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$name" "expected non-zero exit: $*"; else pass "$name"; fi
}

assert_contains() {  # assert_contains <name> <needle> <haystack>
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "missing '$2'"; fi
}

assert_not_contains() {
  if [[ "$3" != *"$2"* ]]; then pass "$1"; else fail "$1" "unexpectedly found '$2'"; fi
}

assert_eq() {  # assert_eq <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}

finish() {
  printf '%s: %d run, %d failed\n' "${TEST_NAME:-tests}" "$TESTS_RUN" "$TESTS_FAILED"
  [[ $TESTS_FAILED -eq 0 ]]
}

make_tmpdir() { mktemp -d "${TMPDIR:-/tmp}/bqpmq.XXXXXX"; }
