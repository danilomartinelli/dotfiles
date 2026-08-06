# System-wide environment variables
# Non-sensitive defaults that apply to all sessions

# Set default umask (user: rwx, group: rx, others: rx)
umask 022

# Set default pager
export PAGER="less"
export LESS="-R"

# Default browser (override in .localrc). A bare `open` delegates to the
# macOS default browser; multi-word values with embedded quotes break every
# consumer that word-splits $BROWSER.
export BROWSER="${BROWSER:-open}"
