#!/bin/sh
#
# Resolve the Homebrew executable and installation prefix for every caller.

find_brew_binary() {
  brew_binary=$(command -v brew 2>/dev/null) || brew_binary=
  if [ -n "$brew_binary" ] && [ -x "$brew_binary" ]; then
    printf '%s\n' "$brew_binary"
    return 0
  fi

  for brew_binary in \
    /opt/homebrew/bin/brew \
    /usr/local/bin/brew \
    /home/linuxbrew/.linuxbrew/bin/brew; do
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
  elif [ -d /opt/homebrew ]; then
    printf '%s\n' /opt/homebrew
  elif [ -d /usr/local/Homebrew ]; then
    printf '%s\n' /usr/local
  else
    printf '%s\n' /usr/local
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
