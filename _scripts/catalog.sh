#!/bin/sh
#
# The one reader for this repository's tab-separated catalogs.
#
# Source it, then call catalog_check and catalog_each_row. Every catalog shares
# the same shape, so the rules for reading one belong here rather than at each
# consumer: what counts as a comment, whether a final row without a trailing
# newline is delivered, which file descriptor the rows arrive on, and how a
# rejected row is reported. What makes a row valid is each catalog's own fact,
# and lives in a rules file beside its consumer.

# Call <handler> once per data row of <catalog>, passing the row's columns as
# arguments. A row is padded with empty strings to seven, so a handler always
# receives seven and may read only the leading ones it declares. Seven is wider
# than any catalog here declares, and deliberately not the widest a consumer
# happens to need: an arity that fits some catalogs and not others is what once
# made a wide catalog grow readers of its own. A row with more columns than
# that packs its tail into the last argument, so widening a catalog past seven
# means widening the read below first.
#
# Blank rows and rows whose first column starts with "#" are skipped. A final
# row without a trailing newline is still delivered, which is the case a
# hand-edited catalog reaches first.
#
# Rows arrive on file descriptor 3, leaving stdin free. That is the whole
# reason this module exists: a handler that runs duti or dockutil would
# otherwise let that command consume the rows still to be read, and every
# consumer had to rediscover the hazard and pick its own guard. It is also why
# the catalog is a path and never stdin.
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

  # Every physical line counts, comments and blanks included, so a rejection
  # names the line an editor shows.
  _catalog_line=0
  while IFS="$(printf '\t')" read -r \
    _catalog_column_1 _catalog_column_2 _catalog_column_3 _catalog_column_4 \
    _catalog_column_5 _catalog_column_6 _catalog_column_7 <&3 \
    || [ -n "${_catalog_column_1:-}" ]; do
    _catalog_line=$((_catalog_line + 1))
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

  unset _catalog_path _catalog_handler _catalog_line \
    _catalog_column_1 _catalog_column_2 _catalog_column_3 _catalog_column_4 \
    _catalog_column_5 _catalog_column_6 _catalog_column_7
}

# Run <validator> over every data row of <catalog> and report whether any row
# was rejected. A row that is wrong on its text alone is a repository error, so
# a consumer checks its whole catalog before its first effect and before any
# run-once gate. Validating while applying let a typo in the Dock layout's last
# row leave the Dock emptied and never restarted, and a gate checked first hid
# a row broken after the first apply until a reset.
#
# The validator is called exactly like a handler, with the same seven columns
# and the same obligation to return zero. It rejects a row by calling
# catalog_reject, as often as the row has faults, so every fault in the file is
# reported in one run. It decides from the row's text only: whether an app
# exists or a tool accepts a value is a fact about this machine, and stays a
# warning for the handler.
#
# Each rejection is printed on stderr as `<catalog>:<line>: <reason>`, the form
# editors and terminals turn into a link. The consumer adds one line of its own
# voice when this returns non-zero, and stops.
#
# Usage: catalog_check <catalog> <validator>
catalog_check() {
  # A consumer calls this as a condition, where `set -e` does not reach, so a
  # misspelt validator would fail on every row and still report no rejection.
  if ! command -v "$2" >/dev/null 2>&1; then
    printf 'catalog: no such validator: %s\n' "$2" >&2
    return 1
  fi

  _catalog_check_rejections=0
  _catalog_check_seen=''
  _catalog_check_tab=$(printf '\t')
  _catalog_check_newline='
'

  if ! catalog_each_row "$1" "$2"; then
    catalog_check_unset
    return 1
  fi

  if [ "$_catalog_check_rejections" -eq 0 ]; then
    catalog_check_unset
    return 0
  fi

  catalog_check_unset
  return 1
}

catalog_check_unset() {
  unset _catalog_check_rejections _catalog_check_seen _catalog_check_tab \
    _catalog_check_newline
}

# Reject the row the validator was called for. Only meaningful inside a
# validator that catalog_check runs.
# Usage: catalog_reject <reason>
catalog_reject() {
  printf '%s:%s: %s\n' "$_catalog_path" "$_catalog_line" "$1" >&2
  _catalog_check_rejections=$((_catalog_check_rejections + 1))
}

# Reject the row when an earlier row of the same catalog declared the same
# <column> values, naming the line that did. A later row silently overriding an
# earlier one is the fault a hand-edited catalog accumulates without anyone
# noticing, and only the reader knows which rows came before.
# Usage: catalog_reject_duplicate <column>...
catalog_reject_duplicate() {
  _catalog_duplicate_key=$1
  shift
  for _catalog_duplicate_column in "$@"; do
    _catalog_duplicate_key=$_catalog_duplicate_key$_catalog_check_tab$_catalog_duplicate_column
  done

  # Entries are `<line><tab><key><newline>`. Splitting each at its first tab
  # keeps a key that itself holds tabs whole.
  _catalog_duplicate_rest=$_catalog_check_seen
  while [ -n "$_catalog_duplicate_rest" ]; do
    _catalog_duplicate_entry=${_catalog_duplicate_rest%%"$_catalog_check_newline"*}
    _catalog_duplicate_rest=${_catalog_duplicate_rest#*"$_catalog_check_newline"}
    if [ "${_catalog_duplicate_entry#*"$_catalog_check_tab"}" = "$_catalog_duplicate_key" ]; then
      catalog_reject "duplicates line ${_catalog_duplicate_entry%%"$_catalog_check_tab"*}"
      catalog_reject_duplicate_unset
      return 0
    fi
  done

  _catalog_check_seen=$_catalog_check_seen$_catalog_line$_catalog_check_tab$_catalog_duplicate_key$_catalog_check_newline
  catalog_reject_duplicate_unset
}

catalog_reject_duplicate_unset() {
  unset _catalog_duplicate_key _catalog_duplicate_column \
    _catalog_duplicate_rest _catalog_duplicate_entry
}

# Reject the row once for every placeholder in <value> that is not one of the
# names given. A misspelt name is otherwise left literal by catalog_expand, and
# a literal `$HOEM/Downloads` is a path that is merely "not found": a warning on
# the one run that applies it, and then hidden behind the run-once marker.
#
# It takes the same <NAME> <replacement> pairs as catalog_expand and ignores
# the replacements, so a consumer can declare what its catalog honours once,
# in one function that forwards to either, and no name can be accepted here
# without also being expanded there.
#
# A placeholder is a `$` followed by the longest run of letters, digits, and
# underscores that starts with a letter or underscore. Anything else after a
# `$` — `$5`, `$/`, `${` — is not a placeholder and is left alone.
#
# Usage: catalog_reject_undeclared <value> [<NAME> <replacement>...]
catalog_reject_undeclared() {
  _catalog_undeclared_rest=$1
  shift

  _catalog_undeclared_names=' '
  _catalog_undeclared_list=''
  while [ "$#" -gt 1 ]; do
    _catalog_undeclared_names="$_catalog_undeclared_names$1 "
    _catalog_undeclared_list="$_catalog_undeclared_list${_catalog_undeclared_list:+, }\$$1"
    shift 2
  done

  if [ "$#" -ne 0 ]; then
    printf 'catalog: placeholder name has no replacement: %s\n' "$1" >&2
    catalog_reject_undeclared_unset
    return 1
  fi

  while :; do
    case $_catalog_undeclared_rest in
      *'$'*) _catalog_undeclared_rest=${_catalog_undeclared_rest#*\$} ;;
      *) break ;;
    esac

    _catalog_undeclared_name=${_catalog_undeclared_rest%%[![:alnum:]_]*}
    case $_catalog_undeclared_name in
      '' | [0-9]*) continue ;;
    esac

    case $_catalog_undeclared_names in
      *" $_catalog_undeclared_name "*) ;;
      *)
        catalog_reject \
          "unknown placeholder \$$_catalog_undeclared_name (expands ${_catalog_undeclared_list:-nothing})"
        ;;
    esac
  done

  catalog_reject_undeclared_unset
}

catalog_reject_undeclared_unset() {
  unset _catalog_undeclared_rest _catalog_undeclared_names \
    _catalog_undeclared_list _catalog_undeclared_name
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
# that line does not belong in a module everything sources.
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
