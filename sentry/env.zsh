# sentry-cli writes its Zsh completion to its own user directory rather than to
# a Homebrew or Mise share, so the directory has to be announced before
# completion is initialized.
#
# This lives in env.zsh and not completion.zsh on purpose: `_startup.zsh` runs
# compinit after every main topic file and before the completion ones, and a
# `#compdef` file is only picked up if its directory was already in fpath when
# compinit ran. Adding it from completion.zsh would be one step too late.
#
# Guarded on the directory because `sentry` is installed by hand into
# ~/.local/bin rather than declared in Brewfile or mise/config.toml, so a fresh
# machine has the topic without the tool.
if [[ -d "$HOME/.local/share/zsh/site-functions" ]]; then
  fpath=("$HOME/.local/share/zsh/site-functions" $fpath)
fi
