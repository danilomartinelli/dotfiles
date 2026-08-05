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
