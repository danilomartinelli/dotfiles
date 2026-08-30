#!/bin/sh
# Apply the declared Dock layout.

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "configuring dock"

installer_require_command dockutil

CATALOG=${DOTFILES_DOCK_CATALOG:-$TOPIC_DIR/_layout.tsv}

# Checked before the run-once gate: the catalog is a tracked repository file, so
# its absence is a repository error rather than a fact about this machine, and
# hiding it behind an already-applied marker would report it only on the one run
# that still had work to do.
if [ ! -f "$CATALOG" ]; then
  installer_fail "Dock layout catalog not found: $CATALOG"
fi

# The declared layout wipes the Dock before rebuilding it, so it only runs on
# the first apply (or when forced). Daily `dot` runs must never destroy manual
# Dock arrangements — every other installer in this repo preserves user state.
# Editing the catalog therefore does not reapply it; see
# docs/adr/0004-a-catalog-edit-does-not-re-arm-the-dock-rebuild.md.
installer_skip_if_applied dock "dock layout" "dock configured"

WORKSPACE_ROOT=$(installer_workspace_root)

# Rows spell paths the way a person writes them. Only these two expansions
# exist, so a `$` anywhere else stays a literal `$`.
expand_path() {
  printf '%s\n' "$1" \
    | sed -e "s|\$WORKSPACE|$WORKSPACE_ROOT|g" -e "s|\$HOME|$HOME|g"
}

# The warning needs a name a person recognises, and the path already carries
# one: /Applications/Spark Desktop.app is "Spark Desktop", $WORKSPACE is
# "Workspace". Nothing has to restate it in a column.
entry_label() {
  basename -- "$1" .app
}

# One catalog row. Always returns zero: a missing app is a fact about this
# machine, not a reason to stop rebuilding the rest of the Dock.
apply_catalog_row() {
  section=$1
  entry_declared=$2
  view=$3
  display=$4

  if [ -z "$entry_declared" ] || [ -z "$view" ] || [ -z "$display" ]; then
    installer_fail "invalid catalog row: $section $entry_declared   $view   $display"
  fi

  case "$section" in
    apps | others) ;;
    *) installer_fail "unknown catalog section '$section' for $entry_declared" ;;
  esac

  entry_path=$(expand_path "$entry_declared")
  entry_name=$(entry_label "$entry_path")

  if [ ! -e "$entry_path" ]; then
    installer_warn "Skipping $entry_name (not found at $entry_path)"
    return 0
  fi

  set -- --add "$entry_path" --section "$section"

  case "$view" in
    -) ;;
    grid | fan | list | auto) set -- "$@" --view "$view" ;;
    *) installer_fail "unknown catalog view '$view' for $entry_path" ;;
  esac

  case "$display" in
    -) ;;
    folder | stack) set -- "$@" --display "$display" ;;
    *) installer_fail "unknown catalog display '$display' for $entry_path" ;;
  esac

  if dockutil "$@" --no-restart >/dev/null 2>&1; then
    installer_success "Added $entry_name"
  else
    installer_warn "Failed to add $entry_name"
  fi
  return 0
}

if ! dockutil --remove all --no-restart >/dev/null 2>&1 </dev/null; then
  installer_warn "Failed to clear dock"
fi

catalog_each_row "$CATALOG" apply_catalog_row

if killall Dock >/dev/null 2>&1; then
  installer_success "Dock restarted"
else
  installer_warn "Failed to restart Dock"
fi

installer_mark_applied dock

installer_success "dock configured"
