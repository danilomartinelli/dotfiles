# shellcheck shell=bash
#
# The stub binaries fixtures share.
#
# shell-scenario.sh owns *how* a stub is written; this file owns *what* the
# stubs are. Two tests standing in for the same command previously each wrote
# their own version and each invented its own failure-injection variable, so
# the same command could mean different things in different files.
#
# Every stub records its call in the event log in one shape:
#
#   <command> <arguments>
#
# which is the convention each hand-written stub used to infer from the others.
#
# Callers pass the fake-bin directory that will be first on PATH. Nothing here
# depends on shell-scenario.sh, so a test using a different harness can still
# share the stubs rather than write its own.

_stub_write() {
  mkdir -p "$(dirname -- "$1")"
  cat >"$1"
  chmod +x "$1"
}

# The platform every installer checks. Defaults to Darwin because that is what
# this repository targets; a test asserting the non-Darwin skip sets
# FAKE_UNAME=Linux in the environment it invokes with.
# Usage: stub_uname <bin-dir>
stub_uname() {
  _stub_write "$1/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "${FAKE_UNAME:-Darwin}"
EOF
}

# Launch Services default-application assignment. FAIL_DUTI holds a
# space-separated list of identifiers whose assignment fails, so one contract
# covers both a single failing row and several.
# Usage: stub_duti <bin-dir>
stub_duti() {
  _stub_write "$1/duti" <<'EOF'
#!/bin/sh
printf 'duti %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
for failing in ${FAIL_DUTI:-}; do
  [ "$failing" != "$3" ] || exit 1
done
exit 0
EOF
}

# Restarting a system service. FAIL_KILLALL is its exit status, so a test can
# assert the warning a failed restart produces.
# Usage: stub_killall <bin-dir>
stub_killall() {
  _stub_write "$1/killall" <<'EOF'
#!/bin/sh
printf 'killall %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
exit "${FAIL_KILLALL:-0}"
EOF
}

# The package manager. One stub covers every subcommand this repository runs,
# under one convention: FAIL_BREW_<SUBCOMMAND> is an exit status and
# FAKE_BREW_<NOUN> is the output a subcommand prints. A subcommand with
# neither variable set succeeds silently, so a fixture declares only the
# behaviour its scenario depends on.
#
# The name is a parameter because setup_test.sh writes the stub aside as a
# template and has its fake Homebrew installer copy it into place mid-run,
# which is how that suite reaches the not-yet-installed path.
# Usage: stub_brew <bin-dir> [name]
stub_brew() {
  _stub_write "$1/${2:-brew}" <<'EOF'
#!/bin/sh
printf 'brew %s\n' "$*" >> "$SCENARIO_EVENT_LOG"
case "$1" in
  --prefix)
    [ "${FAIL_BREW_PREFIX:-0}" -eq 0 ] || exit "$FAIL_BREW_PREFIX"
    [ -z "${FAKE_BREW_PREFIX:-}" ] || printf '%s\n' "$FAKE_BREW_PREFIX"
    ;;
  update)
    exit "${FAIL_BREW_UPDATE:-0}"
    ;;
  upgrade)
    exit "${FAIL_BREW_UPGRADE:-0}"
    ;;
  tap)
    # `brew tap` with no argument lists; with one it adds.
    if [ "$#" -gt 1 ]; then
      exit "${FAIL_BREW_TAP:-0}"
    fi
    [ -z "${FAKE_BREW_TAPS:-}" ] || printf '%s\n' "$FAKE_BREW_TAPS"
    ;;
  untap)
    exit "${FAIL_BREW_UNTAP:-0}"
    ;;
  list)
    [ "${FAIL_BREW_LIST:-0}" -eq 0 ] || exit "$FAIL_BREW_LIST"
    case "$2" in
      --formula)
        [ -z "${FAKE_BREW_FORMULAE:-}" ] || printf '%s\n' "$FAKE_BREW_FORMULAE"
        ;;
      --cask)
        [ -z "${FAKE_BREW_CASKS:-}" ] || printf '%s\n' "$FAKE_BREW_CASKS"
        ;;
    esac
    ;;
  bundle)
    exit "${FAIL_BREW_BUNDLE:-0}"
    ;;
  trust)
    exit "${FAIL_BREW_TRUST:-0}"
    ;;
esac
exit 0
EOF
}
