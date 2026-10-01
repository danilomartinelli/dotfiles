# shellcheck shell=bash
#
# The one reader for generated regions inside hand-authored Markdown.
#
# A generated region is a named stretch of a file a person also edits — a
# README table — that a renderer regenerates from this repository's
# declarations. It guards against two defects the earlier readers had
# learned: a marker merely mentioned in prose satisfied the substring search
# that stood in for finding a region, so a render could report success having
# replaced nothing, and a last line without a newline vanished.
#
# This module owns what a marker is, the structure regions must have, the
# bytes outside region interiors, and the padding around a body. It does not
# know which region names exist or what they contain. That is the handler's,
# which is why there is no second list of names here to fall out of step with
# the renderer that generates them.

# Print <source-file> with the interior of every generated region replaced by
# what <handler> prints for that region's name.
#
#   Opening marker               Closing marker
#   <!-- generated: <name> -->   <!-- generated-end -->
#
# A marker is a whole unindented line. Nothing else is a marker: indentation,
# trailing whitespace, or a marker quoted inside other text is ordinary text,
# copied through. The name is everything between a marker's fixed parts,
# untrimmed, and must not be empty; a name the handler does not know is the
# handler's to refuse.
#
# The handler is called as `<handler> <name>`, in the calling shell, once per
# region in file order — a name that repeats is rendered at every occurrence.
# It prints the body as complete newline-terminated lines, or nothing for an
# empty body, and fails the render by returning non-zero. The body is set off
# with a blank line on each side, which is where mdformat puts them: it
# separates an HTML block from the table below it, so the render writes what
# the formatter would add rather than fighting it. The source arrives on
# descriptor 4, so a handler command that reads stdin cannot swallow the rest
# of the file.
#
# Everything outside a region's interior, the markers included, is copied byte
# for byte, down to whether the last line ends with a newline. A file with no
# region is refused, because it means the markers were renamed or removed and
# the render would otherwise succeed at doing nothing.
#
# Output streams to stdout as it is produced, so a render that fails may
# already have printed a prefix. That prefix is unusable: a caller renders into
# a staging file and publishes it only when this returns zero. The source is
# only ever read.
#
# Returns 0 on success; 1 for an unreadable source, malformed structure, a file
# without a region, or a failed handler; 2 for invalid usage. Diagnostics go to
# stderr.
#
# Usage: generated_regions_render <source-file> <handler>
# shellcheck disable=SC2094 # The source is only read; diagnostics name it.
generated_regions_render() {
  if [ "$#" -ne 2 ]; then
    printf 'usage: generated_regions_render <source-file> <handler>\n' >&2
    return 2
  fi

  local region_source=$1 region_handler=$2
  local region_line region_end region_kind region_name
  local region_open='' region_opened_at=0 region_count=0 region_number=0

  if ! command -v -- "$region_handler" >/dev/null 2>&1; then
    printf 'generated-region: handler is not a command: %s\n' "$region_handler" >&2
    return 2
  fi

  if [ ! -f "$region_source" ] || [ ! -r "$region_source" ]; then
    printf 'generated-region: not a readable file: %s\n' "$region_source" >&2
    return 1
  fi

  while :; do
    # A last line without a newline still arrives, and region_end remembers
    # that it had none so the copy does not invent one.
    region_end=$'\n'
    if ! IFS= read -r region_line <&4; then
      [ -n "$region_line" ] || break
      region_end=''
    fi
    region_number=$((region_number + 1))

    _generated_region_classify "$region_line"

    case "$region_kind" in
      open)
        if [ -n "$region_open" ]; then
          _generated_region_refuse "$region_source" "$region_number" \
            "opening marker inside region '$region_open' opened on line $region_opened_at"
          return 1
        fi
        if [ -z "$region_name" ]; then
          _generated_region_refuse "$region_source" "$region_number" \
            'opening marker has an empty name'
          return 1
        fi

        # The blank line on each side of the body.
        printf '%s\n\n' "$region_line"
        if ! "$region_handler" "$region_name"; then
          _generated_region_refuse "$region_source" "$region_number" \
            "handler $region_handler failed for region '$region_name'"
          return 1
        fi
        printf '\n'

        region_open=$region_name
        region_opened_at=$region_number
        region_count=$((region_count + 1))
        ;;
      close)
        if [ -z "$region_open" ]; then
          _generated_region_refuse "$region_source" "$region_number" \
            'closing marker without an opening marker'
          return 1
        fi
        printf '%s%s' "$region_line" "$region_end"
        region_open=''
        ;;
      *)
        # The old interior is dropped: the handler has already printed its
        # replacement.
        [ -n "$region_open" ] || printf '%s%s' "$region_line" "$region_end"
        ;;
    esac
  done 4<"$region_source"

  if [ -n "$region_open" ]; then
    _generated_region_refuse "$region_source" "$region_opened_at" \
      "region '$region_open' has no closing marker"
    return 1
  fi

  if [ "$region_count" -eq 0 ]; then
    printf 'generated-region: %s: no generated region\n' "$region_source" >&2
    return 1
  fi
}

# Classify one line, setting region_kind to open, close, or text and
# region_name to an opening marker's name. The names are the caller's locals:
# bash scopes them dynamically, and returning them through a command
# substitution would fork once per line of the file.
_generated_region_classify() {
  region_kind=text
  region_name=''

  case "$1" in
    '<!-- generated-end -->')
      region_kind=close
      ;;
    '<!-- generated: '*' -->')
      region_kind=open
      region_name=${1#'<!-- generated: '}
      region_name=${region_name%' -->'}
      ;;
  esac
}

# Usage: _generated_region_refuse <source-file> <line-number> <reason>
_generated_region_refuse() {
  printf 'generated-region: %s:%s: %s\n' "$1" "$2" "$3" >&2
}
