# shellcheck shell=bash
#
# Shared reader for the managed OpenCode entry catalog. The installer test and
# the documentation test both derive their expectations from it, so the parse
# lives here once. Callers must set REPOSITORY_ROOT.

# shellcheck source=_scripts/catalog.sh
# shellcheck disable=SC1091
source "$REPOSITORY_ROOT/_scripts/catalog.sh"

opencode_catalog_print_row() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

opencode_catalog_rows() {
  catalog_each_row \
    "$REPOSITORY_ROOT/opencode/_managed-entries.tsv" \
    opencode_catalog_print_row
}

opencode_catalog_print_name() {
  [ "$1" = "$OPENCODE_CATALOG_WANTED_KIND" ] || return 0
  printf '%s\n' "$2"
}

opencode_catalog_names() {
  local wanted=$1
  local status

  OPENCODE_CATALOG_WANTED_KIND=$wanted
  if catalog_each_row \
    "$REPOSITORY_ROOT/opencode/_managed-entries.tsv" \
    opencode_catalog_print_name; then
    status=0
  else
    status=$?
  fi
  unset OPENCODE_CATALOG_WANTED_KIND
  return "$status"
}

opencode_catalog_has() {
  local wanted_kind=$1
  local wanted_name=$2

  opencode_catalog_names "$wanted_kind" | grep -Fqx -- "$wanted_name"
}

# An entry is a directory or a file according to its repository source, so the
# catalog never restates a shape the checkout already fixes.
opencode_entry_is_directory() {
  [[ -d $REPOSITORY_ROOT/opencode/$1 ]]
}
