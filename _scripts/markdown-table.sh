# shellcheck shell=bash
#
# Rendering generated tables into hand-written Markdown.
#
# Two renderers write tables into documentation this repository also edits by
# hand — the software catalog into README.md and the profile routing into
# opencode/README.md — so the marker syntax, the padding, and what happens to
# the prose around a table are decided once here.

# Read tab-separated rows on stdin and print a Markdown table with <header>,
# itself tab-separated. Cells are padded to the widest in their column, which
# is what mdformat would do to the table anyway; rendering it already
# normalized keeps the formatter and the renderer from disagreeing about a
# file they both write.
#
# Usage: markdown_table <tab-separated-header>
markdown_table() {
  awk -F'\t' -v header="$1" '
    BEGIN {
      columns = split(header, heading, "\t")
      for (column = 1; column <= columns; column++) {
        width[column] = length(heading[column])
      }
    }
    {
      for (column = 1; column <= NF; column++) {
        rows[NR, column] = $column
        if (length($column) > width[column]) {
          width[column] = length($column)
        }
      }
      total = NR
    }
    END {
      line = "|"
      rule = "|"
      for (column = 1; column <= columns; column++) {
        line = line sprintf(" %-*s |", width[column], heading[column])
        dashes = ""
        while (length(dashes) < width[column]) {
          dashes = dashes "-"
        }
        rule = rule " " dashes " |"
      }
      print line
      print rule
      for (row = 1; row <= total; row++) {
        line = "|"
        for (column = 1; column <= columns; column++) {
          line = line sprintf(" %-*s |", width[column], rows[row, column])
        }
        print line
      }
    }
  '
}

# Print <markdown-file> with every marked region replaced by what <handler>
# prints for that region's name. A marked region opens with
#
#   <!-- generated: <name> -->
#
# and closes with `<!-- generated-end -->`; everything between is dropped and
# everything outside is copied through, so the hand-written prose around a
# table survives every render.
#
# The handler is called as `<handler> <name>` and must print the block body.
# A file with no marked region is an error rather than a silent no-op: it means
# the markers were renamed or removed and the render would quietly do nothing.
#
# Usage: markdown_render_blocks <markdown-file> <handler>
markdown_render_blocks() {
  local source_path=$1
  local handler=$2
  local block=''
  local line

  grep -Fq '<!-- generated: ' "$source_path" || {
    printf 'markdown: no generated blocks in %s\n' "$source_path" >&2
    return 1
  }

  while IFS= read -r line; do
    case "$line" in
      '<!-- generated: '*' -->')
        if [ -n "$block" ]; then
          printf 'markdown: nested generated marker: %s\n' "$line" >&2
          return 1
        fi
        block=${line#'<!-- generated: '}
        block=${block%' -->'}
        # mdformat separates an HTML block from the table below it, so the
        # render writes the blank lines the formatter would add rather than
        # fighting it.
        printf '%s\n\n' "$line"
        "$handler" "$block" || return 1
        printf '\n'
        ;;
      '<!-- generated-end -->')
        if [ -z "$block" ]; then
          printf 'markdown: generated-end without an opening marker\n' >&2
          return 1
        fi
        block=''
        printf '%s\n' "$line"
        ;;
      *)
        [ -n "$block" ] || printf '%s\n' "$line"
        ;;
    esac
  done <"$source_path"

  if [ -n "$block" ]; then
    printf 'markdown: unterminated generated block: %s\n' "$block" >&2
    return 1
  fi
}
