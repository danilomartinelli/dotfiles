#!/usr/bin/env bash
#
# The Mobile Readiness record, and the only place one becomes output.
#
# Both Mobile Targets answer the same question — what is this machine's state
# and what may happen next — and answered it in two shapes. iOS committed two
# fields and mapped them to prose in a `case`; Android committed seven and
# accumulated prose against a `failed` counter. Each spelled its own ready
# rule, and Android spelled its twice. Neither could be observed without
# reading its own global names, which is why the suite asserted on seven of
# them by hand.
#
# An adapter fills a record. It does not print, and it does not reach back into
# mobile-setup for print_next_step, which both used to do and neither defined.
# That upward call is why sourcing either module standalone was broken, and why
# a test had to define the function before it could call anything.

# The target this record describes. Read by callers and by the suite rather than
# by this module, which is what SC2034 sees.
# shellcheck disable=SC2034
MOBILE_READINESS_TARGET=''
# The action the observed conditions permit; `none` means ready. This is the
# record's machine-readable half and the only ready rule there is.
MOBILE_READINESS_ACTION=''
# The verdict as a person reads it, newline-terminated per line. Android's is
# several lines because several conditions can fail at once; iOS's is one.
MOBILE_READINESS_REPORT=''

# Open a record. Every field resets together, so a caller never reads a verdict
# that is half this run and half the last one.
# Usage: mobile_readiness_begin <target>
mobile_readiness_begin() {
  MOBILE_READINESS_TARGET=$1
  MOBILE_READINESS_ACTION=''
  MOBILE_READINESS_REPORT=''
}

# Usage: mobile_readiness_line <text>
mobile_readiness_line() {
  MOBILE_READINESS_REPORT="$MOBILE_READINESS_REPORT$1"$'\n'
}

# The follow-up a person performs by hand. One indent, one wording, one owner.
# Usage: mobile_readiness_next_step <text>
mobile_readiness_next_step() {
  mobile_readiness_line "  Next step: $1"
}

# The single ready rule. It keeps a function because four call sites ask it and
# the record's whole machine-readable half is this one comparison; the setter it
# used to sit beside did not, because `mobile_readiness_commit x` is strictly
# longer than the assignment it wrapped.
mobile_readiness_is_ready() {
  [ "$MOBILE_READINESS_ACTION" = none ]
}

# Print the record and report whether it is ready. Every readiness verdict in
# this program leaves through here.
#
# An incomplete verdict is a diagnosis a person has to act on, so it goes to
# stderr where CODING_STANDARDS.md puts warnings, and where the caller's own
# hint about it already went: xcode/install.sh used to split one message across
# two streams because this half arrived on the other one. A ready verdict is
# not a warning and stays on stdout.
mobile_readiness_report() {
  if mobile_readiness_is_ready; then
    printf '%s' "$MOBILE_READINESS_REPORT"
    return 0
  fi
  printf '%s' "$MOBILE_READINESS_REPORT" >&2
  return 1
}
