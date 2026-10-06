#!/bin/sh
# shellcheck disable=SC2317 # The standalone exit fallback is unreachable when sourced.
# Shared preamble for topic installers.
#
# Source after set -e / set -eu from topic/install.sh.
# Optional: set INSTALLER_ANCHOR when $0 is wrong (e.g. bash via BASH_SOURCE).

_installer_anchor=${INSTALLER_ANCHOR:-$0}

_installer_topic_dir=$(CDPATH='' cd -P -- "$(dirname -- "$_installer_anchor")" && pwd) || {
  echo "installer-preamble: cannot resolve topic directory: $_installer_anchor" >&2
  unset _installer_anchor _installer_topic_dir INSTALLER_ANCHOR
  return 1 2>/dev/null || exit 1
}

_installer_dotfiles_root=$(CDPATH='' cd -P -- "$_installer_topic_dir/.." && pwd) || {
  echo "installer-preamble: cannot resolve checkout root from: $_installer_topic_dir" >&2
  unset _installer_anchor _installer_topic_dir _installer_dotfiles_root INSTALLER_ANCHOR
  return 1 2>/dev/null || exit 1
}

TOPIC_DIR=$_installer_topic_dir
DOTFILES_ROOT=$_installer_dotfiles_root
export TOPIC_DIR DOTFILES_ROOT
unset _installer_anchor _installer_topic_dir _installer_dotfiles_root INSTALLER_ANCHOR

# Every installer that reads a catalog reads it through this module.
# shellcheck source=_scripts/catalog.sh
. "$DOTFILES_ROOT/_scripts/catalog.sh"

# The progress vocabulary. Sourced rather than defined here so the modules an
# installer calls out to — link-config, and the _macos scripts setup runs — can
# print in the same voice without also taking checkout resolution, the run-once
# marker directory, and file-type associations.
# shellcheck source=_scripts/installer-output.sh
# shellcheck disable=SC1091
. "$DOTFILES_ROOT/_scripts/installer-output.sh"

installer_require_darwin() {
  if [ "$(uname -s)" != "Darwin" ]; then
    exit 0
  fi
}

# Hard dependency on a CLI command: stop the installer when it is missing.
# Usage: installer_require_command <command> [formula]
# The Homebrew formula defaults to the command name.
installer_require_command() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  installer_error "$1 is required but not installed"
  installer_hint "Install with: brew install ${2:-$1}"
  exit 1
}

# Optional dependency on a CLI command: skip the rest of the installer (exit 0)
# when it is missing, mirroring installer_optional_app. The reason says what the
# remaining work would have done, because the command name alone does not.
# Usage: installer_optional_command <command> <reason> [formula]
# The Homebrew formula defaults to the command name.
installer_optional_command() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  installer_warn "$2"
  installer_hint "Install with: brew install ${3:-$1}"
  exit 0
}

# Optional app dependency: skip the rest of the installer (exit 0) when no
# candidate path exists, mirroring installer_require_darwin. When one exists,
# INSTALLER_APP holds the first match for manual UI follow-up by the user.
# Usage: installer_optional_app <name> <cask> </Applications/Name.app>...
installer_optional_app() {
  _installer_app_name=$1
  _installer_app_cask=$2
  shift 2
  for _installer_app_candidate in "$@"; do
    if [ -d "$_installer_app_candidate" ]; then
      # shellcheck disable=SC2034  # consumed by the sourcing installer
      INSTALLER_APP=$_installer_app_candidate
      unset _installer_app_name _installer_app_cask _installer_app_candidate
      return 0
    fi
  done
  installer_warn "$_installer_app_name not installed yet; skipping"
  installer_hint "Install with: brew install --cask $_installer_app_cask"
  exit 0
}

# The directory a tool reads its configuration from. Spelled the way the tool
# spells it: XDG_CONFIG_HOME is deliberately ignored, because honouring it is
# each tool's fact to state rather than ours to assume on its behalf. Resolves
# only, so the path stays safe to compute: linking into it creates it, and any
# other caller creates it itself.
# Usage: installer_config_dir <tool>
installer_config_dir() {
  printf '%s\n' "$HOME/.config/$1"
}

# The Workspace root. Lives here rather than in the workspace topic because two
# topics have to agree on it: workspace/install.sh builds the layout under it,
# and the Dock catalog places it beside the trash. Resolves only; the caller
# creates the directory, so the path stays safe to compute.
# Usage: installer_workspace_root
installer_workspace_root() {
  printf '%s\n' "${WORKSPACE:-$HOME/Workspace}"
}

# Where run-once markers live. Honours XDG_STATE_HOME where
# installer_config_dir ignores XDG_CONFIG_HOME, because this path is ours: no
# tool has to agree with us about where our own markers sit. Private: the
# run-once module is its only consumer.
_installer_state_dir() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
}

# Apply a step once, preserving later installer work when it is skipped.
# Call directly under set -e, like catalog_each_row: testing the call in a
# conditional would disable error handling inside a shell-function step.
# Usage: installer_run_once <key> <label> <command> [argument...]
installer_run_once() {
  _installer_once_marker=$(_installer_state_dir)/$1-applied
  case " ${DOTFILES_RESET:-} " in
    *" $1 "* | *" all "*) rm -f -- "$_installer_once_marker" ;;
    *)
      if [ -f "$_installer_once_marker" ]; then
        installer_note "$2 already applied; run DOTFILES_RESET=$1 dot to reapply"
        unset _installer_once_marker
        return 0
      fi
      ;;
  esac

  shift 2
  "$@"
  mkdir -p "$(dirname -- "$_installer_once_marker")"
  touch "$_installer_once_marker"
  unset _installer_once_marker
}

# Apply a topic's declared file-type associations and report the outcome.
# Reads TOPIC_DIR/_associations.tsv so a topic gains an association by editing
# data, and checks the whole catalog before the first duti call. A "report" row
# names and counts its failure; an "ignore" row is best-effort, because Launch
# Services does not recognise every identifier on every macOS version. A "-"
# label falls back to the identifier.
# Usage: installer_apply_associations <name> <bundle> <success>
installer_apply_associations() {
  _installer_check_associations
  _installer_apply_checked_associations "$@"
}

# Stop the installer unless TOPIC_DIR/_associations.tsv is readable and every
# row satisfies _installer_check_association. Private: the claim checks before
# its run-once gate, and the apply before its first effect.
_installer_check_associations() {
  _installer_assoc_catalog=$TOPIC_DIR/_associations.tsv

  if [ ! -r "$_installer_assoc_catalog" ]; then
    installer_fail "association catalog not readable: $_installer_assoc_catalog"
  fi

  if ! catalog_check "$_installer_assoc_catalog" _installer_check_association; then
    installer_fail "invalid association catalog: $_installer_assoc_catalog"
  fi

  unset _installer_assoc_catalog
}

# What an association row must satisfy on its text alone. Whether Launch
# Services knows the identifier is a fact about this machine, which is what the
# failure mode is for. Roles are duti's.
# Usage: catalog_check <catalog> _installer_check_association
_installer_check_association() {
  case $2 in
    '') catalog_reject 'missing role' ;;
    all | viewer | editor | shell | none) ;;
    *) catalog_reject "unknown role '$2'" ;;
  esac

  # An unknown mode is a catalog bug, and defaulting it either way would
  # decide silently whether a failure is heard.
  case $3 in
    '') catalog_reject 'missing failure mode' ;;
    report | ignore) ;;
    *) catalog_reject "unknown failure mode '$3'" ;;
  esac

  [ -n "$4" ] || catalog_reject "missing label (use '-' for the identifier)"
  [ -z "$2" ] || catalog_reject_duplicate "$1" "$2"

  return 0
}

# The applying half, for a catalog already checked. Private, so the claim can
# check before its gate without checking the catalog twice.
_installer_apply_checked_associations() {
  _installer_assoc_name=$1
  _installer_assoc_bundle=$2
  _installer_assoc_success=$3
  _installer_assoc_failed=0

  catalog_each_row "$TOPIC_DIR/_associations.tsv" _installer_apply_association

  if [ "$_installer_assoc_failed" -eq 0 ]; then
    installer_success "$_installer_assoc_success"
  else
    installer_warn \
      "Some $_installer_assoc_name file associations could not be configured ($_installer_assoc_failed failed)"
  fi

  unset _installer_assoc_name _installer_assoc_bundle _installer_assoc_success \
    _installer_assoc_failed
}

# One association row, already checked. Counts into _installer_assoc_failed,
# which the caller owns, and always returns zero so a reported failure does not
# stop the run.
_installer_apply_association() {
  _installer_assoc_id=$1
  _installer_assoc_role=$2
  _installer_assoc_failure=$3
  _installer_assoc_label=$4

  if duti -s "$_installer_assoc_bundle" "$_installer_assoc_id" \
    "$_installer_assoc_role" 2>/dev/null; then
    return 0
  fi

  [ "$_installer_assoc_failure" = report ] || return 0

  if [ "$_installer_assoc_label" = '-' ]; then
    _installer_assoc_label=$_installer_assoc_id
  fi
  installer_warn \
    "Failed to set $_installer_assoc_name as default for $_installer_assoc_label"
  _installer_assoc_failed=$((_installer_assoc_failed + 1))
  return 0
}

# Check even an already-claimed catalog; the run-once module owns the rest of
# its lifecycle. Derive the key from the topic so installers never spell it.
# Usage: installer_claim_file_types <name> <bundle> <applied>
installer_claim_file_types() {
  _installer_check_associations

  installer_run_once "$(basename -- "$TOPIC_DIR")-associations" 'file associations' \
    _installer_claim_checked_file_types "$@"
  installer_success "$1 configured"
}

# Missing duti leaves the step armed. Keep this guard inside the step so a
# previously applied claim does not need duti just to report its marker.
_installer_claim_checked_file_types() {
  installer_optional_command duti \
    "duti is required to set $1 as the default app for its declared file types"
  _installer_apply_checked_associations "$@"
}

installer_link_config() {
  "$DOTFILES_ROOT/_scripts/link-config" "$@"
}

# Link a file this repository owns into a tool's configuration directory. The
# steps every linking topic spelled out — resolve the directory, compose the
# destination — are implementation here, so a topic states the tool, the label,
# and the file and nothing about where any of them land. The linker creates the
# directory.
#
# The destination keeps the source's name. No topic links a file under a different
# one, and an argument for that would widen the interface for a case that does
# not exist. A topic linking outside $HOME/.config, or under a policy other
# than the default, calls installer_link_config directly.
# Usage: installer_link_tool_config <tool> <label> <file>
installer_link_tool_config() {
  installer_link_config --label "$2" \
    "$TOPIC_DIR/$3" "$(installer_config_dir "$1")/$3"
}

# Report an operational failure and stop the installer.
# Usage: installer_fail <message>
installer_fail() {
  installer_error "$*"
  exit 1
}
