# shellcheck shell=bash
#
# Shared reader for the managed OpenCode entry catalog. The installer test and
# the documentation test both derive their expectations from it, so the parse
# lives here once. Callers must set REPOSITORY_ROOT.

opencode_catalog_rows() {
  local kind name clone

  while IFS=$'\t' read -r kind name clone; do
    case $kind in
      '' | \#*) continue ;;
    esac
    printf '%s\t%s\t%s\n' "$kind" "$name" "$clone"
  done <"$REPOSITORY_ROOT/opencode/_managed-entries.tsv"
}

opencode_catalog_names() {
  local wanted=$1
  local kind name clone

  while IFS=$'\t' read -r kind name clone; do
    if [[ $kind == "$wanted" ]]; then
      printf '%s\n' "$name"
    fi
  done < <(opencode_catalog_rows)
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
