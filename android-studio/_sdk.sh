#!/bin/sh
#
# Resolve the Android SDK location: the root and the tool directories that
# belong on PATH. path.zsh only exports what this file answers.

# Android Studio installs under an absolute path, so a test that wants it inside
# a fixture tree has no way in. DOTFILES_ANDROID_HOME is that way in, as
# DOTFILES_HOMEBREW_ROOT is for Homebrew.

sdk_root() {
  if [ -n "${DOTFILES_ANDROID_HOME:-}" ]; then
    printf '%s\n' "$DOTFILES_ANDROID_HOME"
    return 0
  fi

  printf '%s\n' "$HOME/Library/Android/sdk"
}

# The directories holding the CLIs the rest of the repository declares, in the
# order a caller should search them. They are printed whether or not they exist
# yet, because shell startup has always placed them ahead of a `mobile-setup`
# that creates them, and a PATH entry for an absent directory costs nothing.
sdk_path() {
  root=$(sdk_root)

  printf '%s:%s:%s\n' \
    "$root/cmdline-tools/latest/bin" \
    "$root/emulator" \
    "$root/platform-tools"
}

usage() {
  printf 'Usage: %s root|path\n' "$0" >&2
}

if [ "$#" -eq 1 ] && [ "$1" = root ]; then
  sdk_root
elif [ "$#" -eq 1 ] && [ "$1" = path ]; then
  sdk_path
else
  usage
  exit 2
fi
