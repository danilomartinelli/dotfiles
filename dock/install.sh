#!/bin/sh
# Apply the declared Dock layout.

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

# shellcheck source=dock/_layout-rules.sh
. "$TOPIC_DIR/_layout-rules.sh"

installer_require_darwin
installer_banner "configuring dock"

installer_require_command dockutil

CATALOG=${DOTFILES_DOCK_CATALOG:-$TOPIC_DIR/_layout.tsv}

# Checked before the run-once gate: the catalog is a tracked repository file, so
# its absence or a malformed row is a repository error rather than a fact about
# this machine, and hiding it behind an already-applied marker would report it
# only on the one run that still had work to do. Checking the whole layout is
# also what keeps a typo in its last row from leaving the Dock cleared.
if [ ! -f "$CATALOG" ]; then
  installer_fail "Dock layout catalog not found: $CATALOG"
fi

if ! catalog_check "$CATALOG" dock_layout_check_row; then
  installer_fail "invalid Dock layout catalog: $CATALOG"
fi

# The warning needs a name a person recognises, and the path already carries
# one: /Applications/Spark Desktop.app is "Spark Desktop", $WORKSPACE is
# "Workspace". Nothing has to restate it in a column.
entry_label() {
  basename -- "$1" .app
}

# One catalog row, already checked. Always returns zero: a missing app is a
# fact about this machine, not a reason to stop rebuilding the rest of the Dock.
apply_catalog_row() {
  section=$1
  view=$3
  display=$4

  entry_path=$(dock_layout_placeholders catalog_expand "$2" "$WORKSPACE_ROOT")
  entry_name=$(entry_label "$entry_path")

  if [ ! -e "$entry_path" ]; then
    installer_warn "Skipping $entry_name (not found at $entry_path)"
    return 0
  fi

  # A "-" omits the flag.
  set -- --add "$entry_path" --section "$section"
  [ "$view" = - ] || set -- "$@" --view "$view"
  [ "$display" = - ] || set -- "$@" --display "$display"

  if dockutil "$@" --no-restart >/dev/null 2>&1; then
    installer_success "Added $entry_name"
  else
    installer_warn "Failed to add $entry_name"
  fi
  return 0
}

apply_dock_layout() {
  WORKSPACE_ROOT=$(installer_workspace_root)

  if ! dockutil --remove all --no-restart >/dev/null 2>&1 </dev/null; then
    installer_warn "Failed to clear dock"
  fi

  catalog_each_row "$CATALOG" apply_catalog_row

  if killall Dock >/dev/null 2>&1; then
    installer_success "Dock restarted"
  else
    installer_warn "Failed to restart Dock"
  fi
}

# Rebuilding would overwrite manual arrangements, so catalog edits take effect
# only on the first apply or an explicit reset.
installer_run_once dock "dock layout" apply_dock_layout
installer_success "dock configured"
