# ZSH Monokai Theme
source ~/.z-monokai

# Detect Homebrew prefix dynamically (works for both Intel and Apple Silicon)
if command -v brew >/dev/null 2>&1; then
  HOMEBREW_PREFIX=$(brew --prefix)
elif [ -d /opt/homebrew ]; then
  HOMEBREW_PREFIX=/opt/homebrew
elif [ -d /usr/local/Homebrew ]; then
  HOMEBREW_PREFIX=/usr/local
else
  HOMEBREW_PREFIX=/usr/local
fi

if [ -f "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

ZSH_HIGHLIGHT_STYLES[path]=
ZSH_HIGHLIGHT_STYLES[path_pathseparator]=fg=black,bold
ZSH_HIGHLIGHT_STYLES[path_prefix]=
