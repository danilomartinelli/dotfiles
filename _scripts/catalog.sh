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

# Expand the placeholders a catalog value declares, and only those.
#
# A catalog row spells paths the way a person writes them — `$HOME/Downloads`,
# `$WORKSPACE`, `$DOTFILES_ROOT/README.md`. Which names a catalog honours is its
# own fact, so a caller passes each name with the value it stands for; this owns
# the grammar and the rule that everything else stays literal. Four consumers
# each carried their own answer before this existed, in three token conventions
# and three mechanisms, and two of them had no test at all.
#
# A name is passed with its replacement rather than read out of the environment
# on the caller's behalf. Indirect expansion needs `eval` under `set -u`, and
# docs/adr/0002-one-reset-variable-for-run-once-steps.md already declined to put
# that line in a module everything sources.
#
# Names apply left to right, so a replacement may contain a token a later name
# expands. No replacement is rescanned for the name that produced it.
#
# A token ends where the name ends — there is no delimiter — so one honoured
# name must not prefix another. Declaring HOME beside HOMEBREW_PREFIX would
# rewrite `$HOMEBREW_PREFIX` as `<home>BREW_PREFIX` with no error. No catalog
# declares such a pair; a catalog that needs one has to spell the longer name
# first and is still wrong on the shorter, so the answer is a different name.
#
# Usage: catalog_expand <value> <NAME> <replacement> [<NAME> <replacement>...]
catalog_expand() {
  _catalog_expand_result=$1
  shift

  while [ "$#" -gt 1 ]; do
    _catalog_expand_token=\$$1
    _catalog_expand_replacement=$2
    shift 2

    _catalog_expand_done=''
    _catalog_expand_rest=$_catalog_expand_result
    while :; do
      case $_catalog_expand_rest in
        *"$_catalog_expand_token"*)
          _catalog_expand_done=$_catalog_expand_done${_catalog_expand_rest%%"$_catalog_expand_token"*}$_catalog_expand_replacement
          _catalog_expand_rest=${_catalog_expand_rest#*"$_catalog_expand_token"}
          ;;
        *)
          _catalog_expand_done=$_catalog_expand_done$_catalog_expand_rest
          break
          ;;
      esac
    done
    _catalog_expand_result=$_catalog_expand_done
  done

  if [ "$#" -ne 0 ]; then
    printf 'catalog: expansion name has no replacement: %s\n' "$1" >&2
    catalog_expand_unset
    return 1
  fi

  printf '%s\n' "$_catalog_expand_result"

  catalog_expand_unset
}

# Both exits clear the same names. The refusal used to return before the unset,
# so a caller that mispaired its arguments kept _catalog_expand_result — in a
# module sourced by every installer and by the interactive shell's startup.
catalog_expand_unset() {
  unset _catalog_expand_result _catalog_expand_token _catalog_expand_replacement \
    _catalog_expand_done _catalog_expand_rest
}
