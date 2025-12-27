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

export PATH="$HOMEBREW_PREFIX/bin:$PATH"
export HOMEBREW_NO_ENV_HINTS=1
