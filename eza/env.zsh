# eza reads its theme from ~/Library/Application Support/eza on macOS and
# ignores XDG_CONFIG_HOME; this is the one variable that moves it to where
# eza/install.sh links the theme.
export EZA_CONFIG_DIR="$HOME/.config/eza"
