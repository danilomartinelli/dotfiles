#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-checkout-tests

# A command acts on the checkout that contains it (docs/adr/0004). Every shell
# exports its active checkout's root, so each case runs with an inherited
# DOTFILES_ROOT that names a different checkout.

test_dot_edit_opens_the_checkout_containing_it() {
  local case_root checkout other

  case_root=$(scenario_tmpdir dot-edit)
  checkout=$case_root/checkout
  other=$case_root/other-checkout
  mkdir -p "$checkout/bin" "$other" "$case_root/elsewhere"
  cp "$REPOSITORY_ROOT/bin/dot" "$checkout/bin/dot"
  chmod +x "$checkout/bin/dot"
  ln -s "$checkout" "$case_root/linked-checkout"

  scenario_write_executable "$case_root/editor" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >"$EDITOR_CAPTURE"
EOF

  edit_from() {
    local directory=$1
    shift
    rm -f "$case_root/opened"
    (
      cd "$directory" || exit 1
      env DOTFILES_ROOT="$other" EDITOR="$case_root/editor" \
        EDITOR_CAPTURE="$case_root/opened" "$@" --edit
    ) || return 1
    command cat "$case_root/opened"
  }

  assert_equal "$checkout" "$(edit_from "$case_root/elsewhere" "$checkout/bin/dot")" \
    'absolute path'
  assert_equal "$checkout" "$(edit_from "$checkout" bin/dot)" 'relative path'
  assert_equal "$checkout" \
    "$(edit_from "$case_root/elsewhere" env PATH="$checkout/bin:/usr/bin:/bin" dot)" \
    'command found on PATH'
  assert_equal "$checkout" \
    "$(edit_from "$case_root/elsewhere" "$case_root/linked-checkout/bin/dot")" \
    'checkout reached through a directory link'
}

# Each adapter hands its whole job to one module of the checkout containing it.
# The modules are stubs that record which file was reached and how; what setup
# and the macOS defaults then do is their own suites' concern.
test_adapters_reach_their_module_in_the_checkout_containing_them() {
  local case_root checkout other

  case_root=$(scenario_tmpdir adapters)
  checkout=$case_root/checkout
  other=$case_root/other-checkout
  mkdir -p "$checkout/bin" "$checkout/_scripts" "$other"
  cp "$REPOSITORY_ROOT/bin/dot" "$REPOSITORY_ROOT/bin/set-defaults" "$checkout/bin/"
  cp "$REPOSITORY_ROOT/_scripts/bootstrap" "$checkout/_scripts/bootstrap"
  chmod +x "$checkout/bin/dot" "$checkout/bin/set-defaults" "$checkout/_scripts/bootstrap"
  scenario_write_executable "$checkout/_scripts/setup" <<'EOF'
#!/bin/sh
printf '%s %s\n' "$0" "$*" >>"$SCENARIO_EVENT_LOG"
EOF
  scenario_write_executable "$checkout/_macos/set-defaults.sh" <<'EOF'
#!/bin/sh
printf '%s %s\n' "$0" "$*" >>"$SCENARIO_EVENT_LOG"
EOF

  reached_by() {
    local run=$case_root/$1
    shift
    scenario_capture "$run" env DOTFILES_ROOT="$other" "$@" || return 1
    command cat "$run/events.log"
  }

  assert_equal "$checkout/_scripts/setup bootstrap" \
    "$(reached_by bootstrap "$checkout/_scripts/bootstrap")" '_scripts/bootstrap'
  assert_equal "$checkout/_scripts/setup update" \
    "$(reached_by dot "$checkout/bin/dot")" 'dot'
  assert_equal "$checkout/_macos/set-defaults.sh " \
    "$(reached_by set-defaults "$checkout/bin/set-defaults")" 'set-defaults'
}

# The regression this pins is a command reading the value its caller exported.
# An executable that names DOTFILES_ROOT assigns it from its own location, or
# takes it from the installer preamble; a sourced file reads the value of the
# process that sourced it, and no file supplies a fallback for an unset root.
test_no_command_reads_an_inherited_root() {
  local path offenders=()

  while IFS= read -r -d '' path; do
    [ -f "$REPOSITORY_ROOT/$path" ] || continue
    grep -q 'DOTFILES_ROOT' "$REPOSITORY_ROOT/$path" || continue
    if grep -Eq '\$\{DOTFILES_ROOT:?[-=?+]' "$REPOSITORY_ROOT/$path"; then
      offenders+=("$path")
      continue
    fi
    [ -x "$REPOSITORY_ROOT/$path" ] || continue
    head -n 1 "$REPOSITORY_ROOT/$path" | grep -q '^#!' || continue
    grep -Eq '^[[:space:]]*(export[[:space:]]+)?DOTFILES_ROOT=|installer-preamble\.sh' \
      "$REPOSITORY_ROOT/$path" || offenders+=("$path")
  done < <(git -C "$REPOSITORY_ROOT" ls-files -z -- ':!tests/' ':!.agents/' ':!.claude/')

  [ "${#offenders[@]}" -eq 0 ] \
    || scenario_fail "files reading an inherited DOTFILES_ROOT: ${offenders[*]}"

  offenders=()
  while IFS= read -r path; do
    offenders+=("$path")
  done < <(git -C "$REPOSITORY_ROOT" grep -l DOTFILES_TEST_ROOT -- ':!tests/checkout_test.sh')
  [ "${#offenders[@]}" -eq 0 ] \
    || scenario_fail "files naming DOTFILES_TEST_ROOT: ${offenders[*]}"
}

scenario_run 'dot --edit opens the checkout containing it' \
  test_dot_edit_opens_the_checkout_containing_it
scenario_run 'adapters reach their module in the checkout containing them' \
  test_adapters_reach_their_module_in_the_checkout_containing_them
scenario_run 'no command reads an inherited checkout root' \
  test_no_command_reads_an_inherited_root
scenario_finish
