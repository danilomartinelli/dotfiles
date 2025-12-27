# System-wide environment variables
# Non-sensitive defaults that apply to all sessions

# Set default umask (user: rwx, group: rx, others: rx)
umask 022

# Increase history size
export HISTSIZE=10000
export SAVEHIST=10000

# Set default pager
export PAGER="less"
export LESS="-R"

# Set default browser (can be overridden in .localrc)
if [ -z "$BROWSER" ]; then
  if [ -d "/Applications/Google Chrome.app" ]; then
    export BROWSER="open -a 'Google Chrome'"
  elif [ -d "/Applications/Safari.app" ]; then
    export BROWSER="open -a Safari"
  fi
fi
