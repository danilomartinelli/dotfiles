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
# when it is missing, mirroring installer_require_app. The reason says what the
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
# Usage: installer_require_app <name> <cask> </Applications/Name.app>...
installer_require_app() {
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

# Where run-once markers live. Private: the run-once helpers are its only
# consumers, and the public config-directory resolver is a separate concern.
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
