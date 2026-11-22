# Homebrew owns the Grok Build version (`grok-build` in the Brewfile). Its own
# updater would install a second copy below ~/.grok that the cask never sees.
export GROK_DISABLE_AUTOUPDATER=1
