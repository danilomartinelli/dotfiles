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
