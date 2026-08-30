#!/bin/sh
#
# Resolve the Homebrew executable and installation prefix for every caller.

# The platform roots Homebrew installs under are absolute, so a test that wants
# them to land in a fixture tree has no way in. DOTFILES_HOMEBREW_ROOT is that
# way in: it prefixes every hardcoded path below and is empty in normal use, so
# the shipped file is the one under test rather than a rewritten copy of it.
BREW_ROOT=${DOTFILES_HOMEBREW_ROOT:-}

find_brew_binary() {
  brew_binary=$(command -v brew 2>/dev/null) || brew_binary=
  if [ -n "$brew_binary" ] && [ -x "$brew_binary" ]; then
    printf '%s\n' "$brew_binary"
    return 0
  fi

  for brew_binary in \
    "$BREW_ROOT/opt/homebrew/bin/brew" \
    "$BREW_ROOT/usr/local/bin/brew" \
    "$BREW_ROOT/home/linuxbrew/.linuxbrew/bin/brew"; do
    if [ -x "$brew_binary" ]; then
      printf '%s\n' "$brew_binary"
      return 0
    fi
  done

  return 1
}

find_brew_prefix() {
  brew_binary=$(find_brew_binary) || return 1
  brew_prefix=$("$brew_binary" --prefix 2>/dev/null) || return 1

  case "$brew_prefix" in
    /*) ;;
    *) return 1 ;;
  esac

  case "$brew_prefix" in
    *'
'*) return 1 ;;
  esac

  [ -d "$brew_prefix" ] || return 1
  printf '%s\n' "$brew_prefix"
}

find_brew_prefix_with_fallback() {
  if brew_prefix=$(find_brew_prefix); then
    printf '%s\n' "$brew_prefix"
  elif [ -d "$BREW_ROOT/opt/homebrew" ]; then
    printf '%s\n' "$BREW_ROOT/opt/homebrew"
  elif [ -d "$BREW_ROOT/usr/local/Homebrew" ]; then
    printf '%s\n' "$BREW_ROOT/usr/local"
  else
    printf '%s\n' "$BREW_ROOT/usr/local"
  fi
}

usage() {
  printf 'Usage: %s binary|prefix [--fallback]\n' "$0" >&2
}

if [ "$#" -eq 1 ] && [ "$1" = binary ]; then
  find_brew_binary
elif [ "$#" -eq 1 ] && [ "$1" = prefix ]; then
  find_brew_prefix
elif [ "$#" -eq 2 ] && [ "$1" = prefix ] && [ "$2" = --fallback ]; then
  find_brew_prefix_with_fallback
else
  usage
  exit 2
fi
