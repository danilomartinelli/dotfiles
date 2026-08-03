#!/usr/bin/env bash

# Shared mechanics for the repository's isolated shell scenario tests.

scenario_cleanup() {
  local scenario_exit_status=$?

  trap - EXIT
  if [ -n "${SCENARIO_ROOT:-}" ] && [ -d "$SCENARIO_ROOT" ]; then
    rm -rf -- "$SCENARIO_ROOT"
  fi
  exit "$scenario_exit_status"
}

scenario_init() {
  local scenario_name=$1

  SCENARIO_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/${scenario_name}.XXXXXX")
  SCENARIO_ROOT=$(CDPATH='' cd -P -- "$SCENARIO_ROOT" && pwd)
  SCENARIO_TESTS_RUN=0
  SCENARIO_TESTS_FAILED=0
  trap scenario_cleanup EXIT
}

scenario_tmpdir() {
  local scenario_label=$1

  mktemp -d "$SCENARIO_ROOT/${scenario_label}.XXXXXX"
}

scenario_write_file() {
  local scenario_path=$1

  mkdir -p -- "$(dirname -- "$scenario_path")"
  command cat > "$scenario_path"
}

scenario_write_executable() {
  local scenario_path=$1

  scenario_write_file "$scenario_path"
  chmod +x "$scenario_path"
}

scenario_capture() {
  local scenario_artifact_dir=$1
  shift

  mkdir -p -- "$scenario_artifact_dir"
  : > "$scenario_artifact_dir/events.log"
  SCENARIO_EVENT_LOG="$scenario_artifact_dir/events.log" \
    "$@" > "$scenario_artifact_dir/stdout.log" 2> "$scenario_artifact_dir/stderr.log"
}

scenario_fail() {
  printf '    %s\n' "$1" >&2
  return 1
}

assert_equal() {
  local expected=$1
  local actual=$2
  local description=$3

  [ "$expected" = "$actual" ] || \
    scenario_fail "$description (expected '$expected', got '$actual')"
}

assert_contains() {
  local file=$1
  local expected=$2

  grep -Fq -- "$expected" "$file" || \
    scenario_fail "Expected $file to contain: $expected"
}

assert_not_contains() {
  local file=$1
  local unexpected=$2

  if grep -Fq -- "$unexpected" "$file"; then
    scenario_fail "Expected $file not to contain: $unexpected"
  fi
}

assert_count() {
  local file=$1
  local pattern=$2
  local expected=$3
  local actual

  actual=$(grep -Fc -- "$pattern" "$file" || true)
  [ "$actual" -eq "$expected" ] || \
    scenario_fail "Expected $expected occurrences of '$pattern' in $file, got $actual"
}

assert_before() {
  local file=$1
  local first_pattern=$2
  local second_pattern=$3
  local first_line
  local second_line

  first_line=$(grep -nF -- "$first_pattern" "$file" | head -n 1 | cut -d: -f1 || true)
  second_line=$(grep -nF -- "$second_pattern" "$file" | head -n 1 | cut -d: -f1 || true)
  [ -n "$first_line" ] || scenario_fail "Missing '$first_pattern' in $file"
  [ -n "$second_line" ] || scenario_fail "Missing '$second_pattern' in $file"
  [ "$first_line" -lt "$second_line" ] || \
    scenario_fail "Expected '$first_pattern' before '$second_pattern' in $file"
}

assert_mode() {
  local path=$1
  local expected=$2
  local actual

  actual=$(stat -f '%Lp' "$path" 2>/dev/null || stat -c '%a' "$path")
  assert_equal "$expected" "$actual" "mode for $path"
}

assert_fails() {
  local description=$1
  shift

  if "$@" > /dev/null 2>&1; then
    scenario_fail "$description (command unexpectedly succeeded)"
  fi
}

assert_fails_with_status() {
  local expected=$1
  shift
  local actual

  if "$@"; then
    actual=0
  else
    actual=$?
  fi
  [ "$actual" -eq "$expected" ] || \
    scenario_fail "Expected status $expected, got $actual"
}

assert_fails_with_output() {
  local description=$1
  local expected=$2
  shift 2
  local actual_output

  if actual_output=$("$@" 2>&1); then
    scenario_fail "$description (command unexpectedly succeeded)"
    return 1
  fi
  case $actual_output in
    *"$expected"*) ;;
    *) scenario_fail "$description (missing error text '$expected')" ;;
  esac
}

scenario_run() {
  local scenario_name=$1
  shift
  local scenario_errexit_enabled=0
  local scenario_status

  SCENARIO_TESTS_RUN=$((SCENARIO_TESTS_RUN + 1))
  case $- in
    *e*)
      scenario_errexit_enabled=1
      set +e
      ;;
  esac
  (set -e; "$@")
  scenario_status=$?
  if [ "$scenario_errexit_enabled" -eq 1 ]; then
    set -e
  fi
  if [ "$scenario_status" -eq 0 ]; then
    printf 'ok %d - %s\n' "$SCENARIO_TESTS_RUN" "$scenario_name"
  else
    SCENARIO_TESTS_FAILED=$((SCENARIO_TESTS_FAILED + 1))
    printf 'not ok %d - %s\n' "$SCENARIO_TESTS_RUN" "$scenario_name"
  fi
}

scenario_finish() {
  printf '1..%d\n' "$SCENARIO_TESTS_RUN"
  if [ "$SCENARIO_TESTS_FAILED" -ne 0 ]; then
    printf '%d test(s) failed\n' "$SCENARIO_TESTS_FAILED" >&2
    return 1
  fi
}
