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

# The selected Xcode's Simulator SDK and runtime inventory. The default
# runtime line is copied from the Xcode 26.6/iOS 26.5 output observed on the
# development machine: available rows have no availability suffix.
# Usage: stub_xcrun <bin-dir>
stub_xcrun() {
  _stub_write "$1/xcrun" <<'EOF'
#!/bin/sh
printf 'xcrun %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
case "$*" in
  '--sdk iphonesimulator --show-sdk-version')
    printf '%s\n' "${FAKE_IOS_SDK_VERSION:-26.5}"
    ;;
  'simctl list runtimes')
    if [ -n "${FAKE_IOS_RUNTIMES+x}" ]; then
      printf '%s\n' "$FAKE_IOS_RUNTIMES"
    elif [ -f "$HOME/.ios-runtime-ready" ]; then
      printf '%s\n' '== Runtimes =='
      printf '%s\n' 'iOS 26.5 (26.5 - 23F77) - com.apple.CoreSimulator.SimRuntime.iOS-26-5'
    fi
    ;;
  *)
    exit 1
    ;;
esac
EOF
}

# Xcode's explicit platform download operation. It only records the call and,
# when requested by a fixture, marks the fake runtime as installed.
# Usage: stub_xcodebuild <bin-dir>
stub_xcodebuild() {
  _stub_write "$1/xcodebuild" <<'EOF'
#!/bin/sh
printf 'xcodebuild %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
if [ "$*" = '-downloadPlatform iOS' ] && [ "${FAKE_XCODEBUILD_INSTALL:-0}" -eq 1 ]; then
  : >"$HOME/.ios-runtime-ready"
fi
exit "${FAKE_XCODEBUILD_STATUS:-0}"
EOF
}

# Mise's Java lookup. The caller supplies the fixture path through
# FAKE_MISE_JAVA_HOME so this never exposes a host installation to a test.
# Usage: stub_mise <bin-dir>
stub_mise() {
  _stub_write "$1/mise" <<'EOF'
#!/bin/sh
if [ "$*" = 'where java' ]; then
  printf '%s\n' "$FAKE_MISE_JAVA_HOME"
  exit 0
fi
exit 1
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
