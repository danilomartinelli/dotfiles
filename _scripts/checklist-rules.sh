#!/bin/sh
#
# What a post-bootstrap checklist row must satisfy on its text alone.
#
# Sourced after _scripts/catalog.sh by _scripts/checklist, which checks the
# whole catalog before it prints anything, and by tests/catalog_rules_test.sh,
# which checks the tracked catalog without printing it. POSIX sh, so the same
# file serves the Bash checklist and the test's sh. Whether a candidate app
# exists is not a rule: it decides which heading the row prints under.
#
# Two rows may share a label on purpose: an app the checklist opens can also
# need a step in its settings, so labels are not unique.

# The placeholders a note honours, declared once. The checklist expands through
# here and the rules reject through here, so no name can be accepted without
# also being expanded.
# Usage: checklist_placeholders <catalog_expand|catalog_reject_undeclared> <value> <dotfiles-root>
checklist_placeholders() {
  "$1" "$2" DOTFILES_ROOT "$3"
}

# Usage: catalog_check <catalog> checklist_check_row
checklist_check_row() {
  [ -n "$2" ] || catalog_reject "missing app (use '-' for none)"
  [ -n "$3" ] || catalog_reject 'missing label'

  if [ -z "$4" ]; then
    catalog_reject 'missing note'
  else
    checklist_placeholders catalog_reject_undeclared "$4" ''
  fi

  case $1 in
    credential | shell)
      case $2 in
        '' | -) ;;
        *) catalog_reject "a $1 row opens no app; use '-': '$2'" ;;
      esac
      ;;
    app)
      case $2 in
        '' | -) ;;
        *) _checklist_check_candidates "$2" ;;
      esac
      ;;
    *) catalog_reject "unknown kind '$1'" ;;
  esac

  return 0
}

# Candidates are "|"-separated absolute .app paths.
_checklist_check_candidates() {
  _checklist_candidates=$1
  while :; do
    _checklist_candidate=${_checklist_candidates%%|*}
    case $_checklist_candidate in
      /*.app) ;;
      *) catalog_reject "not an app path: '$_checklist_candidate'" ;;
    esac
    case $_checklist_candidates in
      *'|'*) _checklist_candidates=${_checklist_candidates#*|} ;;
      *) break ;;
    esac
  done
  unset _checklist_candidates _checklist_candidate
}
