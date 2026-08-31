# shellcheck shell=bash
#
# The verdict a renderer reaches about a file it generates.
#
# Both renderers answer the same question — is what is checked in still what
# this would produce? — and answered it two different ways. One counted stale
# payloads and named their paths; the other printed a unified diff and stopped
# at the first. tests/documentation_test.sh runs both with --check and treats
# the two as interchangeable, which they were not: only one of them showed you
# what had drifted, and only one of them kept going to find the rest.
#
# This is deliberately not the whole renderer shell. The flag loop, the usage
# text, and the temp directory are boilerplate every Bash script has, and a
# module holding them would be four calls a caller has to make in the right
# order. What the two renderers actually disagreed about is the verdict, and
# that is what lives here.

GENERATED_FILE_MODE='write'
GENERATED_FILE_STALE=0

# Usage: generated_file_mode <check|write>
generated_file_mode() {
  GENERATED_FILE_MODE=$1
  GENERATED_FILE_STALE=0
}

# Compare one rendered file against its stored counterpart, then either report
# the difference or write it. Under check the diff goes to stderr, because the
# path alone does not tell you whether the drift was the payload or a stray
# newline.
# Usage: generated_file_sync <rendered> <stored> <display>
generated_file_sync() {
  local rendered=$1 stored=$2 display=$3

  if [ -f "$stored" ] && cmp -s "$rendered" "$stored"; then
    return 0
  fi

  if [ "$GENERATED_FILE_MODE" = check ]; then
    printf 'stale: %s\n' "$display" >&2
    diff -u "$stored" "$rendered" >&2 || true
    GENERATED_FILE_STALE=$((GENERATED_FILE_STALE + 1))
    return 0
  fi

  mkdir -p -- "$(dirname -- "$stored")"
  cp -- "$rendered" "$stored"
  printf '  → rendered %s\n' "$display"
}

# The run's verdict. Silent outside check mode, because a write run has already
# named every file it rewrote.
# Usage: generated_file_verdict <subject> <command>
generated_file_verdict() {
  [ "$GENERATED_FILE_MODE" = check ] || return 0

  if [ "$GENERATED_FILE_STALE" -gt 0 ]; then
    printf '%s out of date (%d file(s)); run %s\n' "$1" "$GENERATED_FILE_STALE" "$2" >&2
    return 1
  fi

  printf '%s up to date.\n' "$1"
}
