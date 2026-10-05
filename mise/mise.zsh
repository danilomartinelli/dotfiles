# The old export bypasses conf.d, including the persistent trust settings.
# Keep explicit overrides pointing somewhere else available to callers.
if [[ ${MISE_GLOBAL_CONFIG_FILE:-} == "$HOME/.config/mise/config.toml" ]]; then
  unset MISE_GLOBAL_CONFIG_FILE
fi

# Project configuration beneath a trusted root needs no `mise trust`.
# _scripts/trusted-roots owns the list, which direnv's whitelist shares.
export MISE_TRUSTED_CONFIG_PATHS="${(j/:/)${(f)"$("$DOTFILES_ROOT/_scripts/trusted-roots")"}}"

# sup mise
# https://mise.jdx.dev/
if (( $+commands[mise] ))
then
  eval "$(mise activate zsh)"
fi
