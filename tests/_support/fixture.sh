# shellcheck shell=bash
#
# The isolated tree an installer runs against.
#
# Every installer fixture needs the same five things: a temp root, a fake
# $HOME, a run-once marker directory, a fake-bin first on PATH, and a way to
# invoke the installer against all of them. Each suite used to build that by
# hand, under its own name, with its own copy of the PATH string.
#
# shell-scenario.sh owns the temp-root lifecycle and the assertions; this file
# owns what an installer fixture *is*. Stubs come from stubs.sh, which the
# caller sources and populates.

# Create a fixture and print its path. The layout is fixed so a test never has
# to state it:
#
#   <fixture>/home        the fake $HOME
#   <fixture>/state       XDG_STATE_HOME, where run-once markers land
#   <fixture>/fake-bin    first on PATH
#
# uname is stubbed here because every installer checks the platform and a test
# that forgot would read the real one. Every other stub is the suite's to add.
#
# Usage: fixture=$(installer_fixture [label])
installer_fixture() {
  local label=${1:-fixture}
  local fixture

  fixture=$(scenario_tmpdir "$label")
  mkdir -p "$fixture/home" "$fixture/state" "$fixture/fake-bin"
  stub_uname "$fixture/fake-bin"
  printf '%s\n' "$fixture"
}

# Run a command against a fixture, capturing stdout, stderr, and the event log.
#
#   fixture_run "$fixture" FAIL_DUTI=zip -- "$REPOSITORY_ROOT/skim/install.sh"
#
# Everything before `--` is a KEY=value passed to this run only. That is the
# whole point: failure injection used to be `export FAIL_X` before the call and
# `unset FAIL_X` after, so a case that returned early between the two leaked its
# injection into the next one.
#
# HOME, XDG_STATE_HOME, and PATH are set from the fixture. DOTFILES_RESET is
# cleared, because a value inherited from the developer's own shell would
# re-arm run-once steps the test expects to be skipped.
#
# --artifacts sends the logs somewhere other than the fixture root, for a suite
# that runs an installer twice and compares the two event logs. The run-once
# marker still lives in the fixture, which is what makes the second run see
# what the first one recorded.
#
# Usage: fixture_run <fixture> [--artifacts <dir>] [KEY=value ...] -- <cmd>...
fixture_run() {
  local fixture=$1
  shift
  local artifacts=$fixture

  if [ "${1-}" = --artifacts ]; then
    artifacts=$2
    shift 2
  fi

  local -a overrides=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    overrides+=("$1")
    shift
  done
  [ "$#" -gt 0 ] || {
    scenario_fail 'fixture_run: missing -- before the command'
    return 1
  }
  shift

  scenario_capture "$artifacts" env -u DOTFILES_RESET \
    HOME="$fixture/home" \
    XDG_STATE_HOME="$fixture/state" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    ${overrides[@]+"${overrides[@]}"} \
    "$@"
}
