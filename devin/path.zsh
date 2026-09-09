# The Devin desktop app links its CLI into Codeium's Windsurf directory rather
# than into a Homebrew prefix, so installing the `devin-cli` cask puts nothing
# on PATH by itself. The directory is Devin's own default on macOS, which makes
# this the tracked spelling of what the app's installer would otherwise append
# to the shell profile.
#
# Appended rather than prepended: the directory holds a single `devin-desktop`
# link, so nothing there needs to win over Homebrew or the system.
export PATH="$PATH:$HOME/.codeium/windsurf/bin"
