# shellcheck shell=bash
#
# Rendering generated tables into hand-written Markdown.
#
# Two renderers write tables into documentation this repository also edits by
# hand — the software catalog into README.md and the profile routing into
# opencode/README.md — so the shape of a table is decided once here. Where a
# table lands, and what happens to the prose around it, is the generated-region
# reader's: see _scripts/generated-region.sh.

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
