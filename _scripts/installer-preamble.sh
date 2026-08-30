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
# only; the caller creates the directory, so the path stays safe to compute.
# See docs/adr/0003-tool-config-directories-are-not-xdg-derived.md.
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
# run-once helpers are its only consumers.
_installer_state_dir() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
}

# Gate for a run-once step: report and skip successfully (exit 0) when the step
# has already been applied, so an update run never rebuilds state the user may
# have rearranged by hand. DOTFILES_RESET re-arms it, accepting a
# space-separated list of keys or the word "all".
# Usage: installer_skip_if_applied <key> <label> <success>
installer_skip_if_applied() {
  case " ${DOTFILES_RESET:-} " in
    *" $1 "* | *" all "*) return 0 ;;
  esac

  _installer_marker=$(_installer_state_dir)/$1-applied
  if [ -f "$_installer_marker" ]; then
    installer_note "$2 already applied; run DOTFILES_RESET=$1 dot to reapply"
    installer_success "$3"
    exit 0
  fi
  unset _installer_marker
}

# Record that a run-once step completed. Deliberately not tolerant of failure:
# an unwritable state directory would silently re-arm the step on the next run.
# Usage: installer_mark_applied <key>
installer_mark_applied() {
  _installer_marker=$(_installer_state_dir)/$1-applied
  mkdir -p "$(dirname -- "$_installer_marker")"
  touch "$_installer_marker"
  unset _installer_marker
}

# Apply a topic's declared file-type associations and report the outcome.
# Reads TOPIC_DIR/_associations.tsv so a topic gains an association by editing
# data. A "report" row names and counts its failure; an "ignore" row is
# best-effort, because Launch Services does not recognise every identifier on
# every macOS version. A "-" label falls back to the identifier.
# Usage: installer_apply_associations <name> <bundle> <success>
installer_apply_associations() {
  _installer_assoc_name=$1
  _installer_assoc_bundle=$2
  _installer_assoc_success=$3
  _installer_assoc_failed=0

  catalog_each_row "$TOPIC_DIR/_associations.tsv" _installer_apply_association \
    || installer_fail "association catalog not readable: $TOPIC_DIR/_associations.tsv"

  if [ "$_installer_assoc_failed" -eq 0 ]; then
    installer_success "$_installer_assoc_success"
  else
    installer_warn \
      "Some $_installer_assoc_name file associations could not be configured ($_installer_assoc_failed failed)"
  fi

  unset _installer_assoc_name _installer_assoc_bundle _installer_assoc_success \
    _installer_assoc_failed
}

# One association row. Counts into _installer_assoc_failed, which the caller
# owns, and always returns zero so a reported failure does not stop the run.
_installer_apply_association() {
  _installer_assoc_id=$1
  _installer_assoc_role=$2
  _installer_assoc_failure=$3
  _installer_assoc_label=$4

  # An unknown mode is a catalog bug, and defaulting it either way would
  # decide silently whether a failure is heard.
  case $_installer_assoc_failure in
    report | ignore) ;;
    *)
      installer_fail \
        "unknown failure mode '$_installer_assoc_failure' for $_installer_assoc_id in $TOPIC_DIR/_associations.tsv"
      ;;
  esac

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

installer_link_config() {
  "$DOTFILES_ROOT/_scripts/link-config" "$@"
}

installer_banner() {
  printf '› %s\n' "$*"
}

installer_success() {
  printf '✓ %s\n' "$*"
}

installer_note() {
  printf '  → %s\n' "$*"
}

installer_warn() {
  printf 'Warning: %s\n' "$*" >&2
}

installer_error() {
  printf 'Error: %s\n' "$*" >&2
}

# Actionable follow-up for the warning or error just emitted, so the whole
# message stays on one stream. Use installer_note for stdout follow-ups.
installer_hint() {
  printf '  → %s\n' "$*" >&2
}

# Report an operational failure and stop the installer.
# Usage: installer_fail <message>
installer_fail() {
  installer_error "$*"
  exit 1
}
