export MISE_GLOBAL_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml"

# sup mise
# https://mise.jdx.dev/
if (( $+commands[mise] ))
then
  eval "$(mise activate zsh)"
fi
