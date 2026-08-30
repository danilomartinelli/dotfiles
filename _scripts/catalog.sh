#!/bin/sh
#
# The one reader for this repository's tab-separated catalogs.
#
# Source it, then call catalog_each_row. Every catalog shares the same shape,
# so the rules for reading one belong here rather than at each consumer: what
# counts as a comment, whether a final row without a trailing newline is
# delivered, and which file descriptor the rows arrive on.

# Call <handler> once per data row of <catalog>, passing the row's columns as
# arguments. A row is padded with empty strings to seven, so a handler always
# receives seven and may read only the leading ones it declares. Seven is the
# widest catalog here rather than the widest a consumer happens to need: an
# arity that fits some catalogs and not others is what made the wide ones grow
# readers of their own. A row with more columns than that packs its tail into
# the last argument, so widening a catalog past seven means widening the read
# below first.
#
# Blank rows and rows whose first column starts with "#" are skipped. A final
# row without a trailing newline is still delivered, which is the case a
# hand-edited catalog reaches first.
#
# Rows arrive on file descriptor 3, leaving stdin free. That is the whole
# reason this module exists: a handler that runs duti, dockutil, or ocx would
# otherwise let that command consume the rows still to be read, and every
# consumer had to rediscover the hazard and pick its own guard.
#
# The handler runs in the calling shell, so it may set variables the caller
# reads afterwards. It must return zero: consumers run under `set -e`, and a
# handler returning non-zero stops the run rather than skipping a row. It must
# also not call catalog_each_row itself: the second call would reuse both
# descriptor 3 and this module's variables. No catalog here nests, and a
# consumer that needs to should read the inner one into a variable first.
#
# Usage: catalog_each_row <catalog> <handler>
catalog_each_row() {
  _catalog_path=$1
  _catalog_handler=$2

  if [ ! -r "$_catalog_path" ]; then
    printf 'catalog: not readable: %s\n' "$_catalog_path" >&2
    return 1
  fi

  while IFS="$(printf '\t')" read -r \
    _catalog_column_1 _catalog_column_2 _catalog_column_3 _catalog_column_4 \
    _catalog_column_5 _catalog_column_6 _catalog_column_7 <&3 \
    || [ -n "${_catalog_column_1:-}" ]; do
    case ${_catalog_column_1:-} in
      '' | '#'*)
        _catalog_column_1=''
        continue
        ;;
    esac

    "$_catalog_handler" \
      "$_catalog_column_1" "${_catalog_column_2:-}" \
      "${_catalog_column_3:-}" "${_catalog_column_4:-}" \
      "${_catalog_column_5:-}" "${_catalog_column_6:-}" \
      "${_catalog_column_7:-}"

    _catalog_column_1=''
  done 3<"$_catalog_path"

  unset _catalog_path _catalog_handler \
    _catalog_column_1 _catalog_column_2 _catalog_column_3 _catalog_column_4 \
    _catalog_column_5 _catalog_column_6 _catalog_column_7
}
