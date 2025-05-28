export MISE_GLOBAL_CONFIG_FILE="$HOME/.mise.toml"

# sup mise
# https://mise.jdx.dev/
if (( $+commands[mise] ))
then
  eval "$(mise activate zsh)"
fi
