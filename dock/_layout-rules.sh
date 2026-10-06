#!/bin/sh
#
# What a Dock layout row must satisfy on its text alone.
#
# Sourced after _scripts/catalog.sh by dock/install.sh, which checks the whole
# layout before it clears the Dock, and by tests/catalog_rules_test.sh, which
# checks the tracked layout without touching one. Whether an entry exists on
# this machine is not a rule: the installer warns about it while applying.

# The placeholders a layout path honours, declared once. The installer expands
# through here and the rules reject through here, so no name can be accepted
# without also being expanded.
# Usage: dock_layout_placeholders <catalog_expand|catalog_reject_undeclared> <value> <workspace-root>
dock_layout_placeholders() {
  "$1" "$2" WORKSPACE "$3" HOME "$HOME"
}

# Usage: catalog_check <layout> dock_layout_check_row
dock_layout_check_row() {
  case $1 in
    apps | others) ;;
    *) catalog_reject "unknown section '$1'" ;;
  esac

  if [ -z "$2" ]; then
    catalog_reject 'missing path'
  else
    dock_layout_placeholders catalog_reject_undeclared "$2" ''
    catalog_reject_duplicate "$2"
  fi

  case $3 in
    '') catalog_reject 'missing view' ;;
    - | grid | fan | list | auto) ;;
    *) catalog_reject "unknown view '$3'" ;;
  esac

  case $4 in
    '') catalog_reject 'missing display' ;;
    - | folder | stack) ;;
    *) catalog_reject "unknown display '$4'" ;;
  esac

  return 0
}
