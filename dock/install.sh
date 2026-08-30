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

apply_catalog() {
  while IFS="$(printf '\t')" read -r section path view display || [ -n "${section:-}" ]; do
    case "${section:-}" in
      '' | \#*)
        section=
        continue
        ;;
    esac

    if [ -z "${path:-}" ] || [ -z "${view:-}" ] || [ -z "${display:-}" ]; then
      installer_fail "invalid catalog row: $section	$path	$view	$display"
    fi

    case "$section" in
      apps | others) ;;
      *) installer_fail "unknown catalog section '$section' for $path" ;;
    esac

    entry_path=$(expand_path "$path")
    entry_name=$(entry_label "$entry_path")

    if [ ! -e "$entry_path" ]; then
      installer_warn "Skipping $entry_name (not found at $entry_path)"
      section=
      continue
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

    # </dev/null keeps dockutil away from the catalog this loop is reading.
    if dockutil "$@" --no-restart >/dev/null 2>&1 </dev/null; then
      installer_success "Added $entry_name"
    else
      installer_warn "Failed to add $entry_name"
    fi

    section=
  done <"$CATALOG"
}

if ! dockutil --remove all --no-restart >/dev/null 2>&1 </dev/null; then
  installer_warn "Failed to clear dock"
fi

apply_catalog

if killall Dock >/dev/null 2>&1; then
  installer_success "Dock restarted"
else
  installer_warn "Failed to restart Dock"
fi

installer_mark_applied dock

installer_success "dock configured"
