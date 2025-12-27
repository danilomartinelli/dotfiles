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

# Add Homebrew paths and legacy /usr/local paths for compatibility
export PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:/usr/local/bin:/usr/local/sbin:$ZSH/bin:$PATH"

# Set MANPATH with dynamic Homebrew prefix
export MANPATH="$HOMEBREW_PREFIX/man:/usr/local/man:/usr/local/mysql/man:/usr/local/git/man:$MANPATH"
