# System-wide environment variables
# Non-sensitive defaults that apply to all sessions

# Set default umask (user: rwx, group: rx, others: rx)
umask 022

# Set default pager
export PAGER="less"
export LESS="-R"

# bat picks a theme by the terminal's background unless told; every tool here
# is fixed on Catppuccin Macchiato, which bat bundles. delta reads its own
# syntax-theme from gitconfig.
export BAT_THEME="Catppuccin Macchiato"

# Default browser (override in .localrc). A bare `open` delegates to the
# macOS default browser; multi-word values with embedded quotes break every
# consumer that word-splits $BROWSER.
export BROWSER="${BROWSER:-open}"
