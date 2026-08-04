# Shared checkout resolution for public adapters.
#
# Source after setting ADAPTER_ANCHOR to the calling script path.
# When ADAPTER_ANCHOR is unset, $0 is used (executed scripts).

_dotfiles_adapter_anchor=${ADAPTER_ANCHOR:-$0}

_dotfiles_root_resolver=$HOME/.dotfiles-root
if [ ! -L "$_dotfiles_root_resolver" ] || [ ! -x "$_dotfiles_root_resolver" ]; then
  _dotfiles_adapter_dir=$(CDPATH='' cd -P -- "$(dirname -- "$_dotfiles_adapter_anchor")" && pwd) || {
    echo "adapter-checkout: cannot resolve adapter directory: $_dotfiles_adapter_anchor" >&2
    unset _dotfiles_adapter_anchor _dotfiles_root_resolver _dotfiles_adapter_dir ADAPTER_ANCHOR
    return 1 2>/dev/null || exit 1
  }
  _dotfiles_root_resolver=$_dotfiles_adapter_dir/../dotfiles-root.symlink
fi

if [ ! -x "$_dotfiles_root_resolver" ]; then
  echo "adapter-checkout: checkout-root resolver not found. Run _scripts/bootstrap first." >&2
  unset _dotfiles_adapter_anchor _dotfiles_root_resolver _dotfiles_adapter_dir ADAPTER_ANCHOR
  return 1 2>/dev/null || exit 1
fi

DOTFILES_ROOT=$("$_dotfiles_root_resolver" "$_dotfiles_adapter_anchor") || {
  unset _dotfiles_adapter_anchor _dotfiles_root_resolver _dotfiles_adapter_dir ADAPTER_ANCHOR
  return 1 2>/dev/null || exit 1
}
export DOTFILES_ROOT
unset _dotfiles_adapter_anchor _dotfiles_root_resolver _dotfiles_adapter_dir ADAPTER_ANCHOR
