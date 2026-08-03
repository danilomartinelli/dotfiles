#!/bin/sh

set -eu

echo "› setting up Workspace layout"

workspace_root=${WORKSPACE:-$HOME/Workspace}
github_root=$workspace_root/github.com

mkdir -p "$github_root"
echo "  ✓ $github_root"

# GitHub handles: 1–39 chars, alphanumeric or hyphen, no leading/trailing hyphen.
is_github_username() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$'
}

resolve_github_user() {
  candidate=

  if [ -n "${GITHUB_USER:-}" ]; then
    candidate=$GITHUB_USER
  elif command -v git >/dev/null 2>&1; then
    candidate=$(git config --global github.user 2>/dev/null || true)
  fi

  if [ -z "$candidate" ] && command -v git >/dev/null 2>&1; then
    git_name=$(git config --global user.name 2>/dev/null || true)
    if [ -n "$git_name" ]; then
      # "Danilo Martinelli" → danilomartinelli
      candidate=$(printf '%s\n' "$git_name" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    fi
  fi

  if [ -z "$candidate" ] && command -v gh >/dev/null 2>&1; then
    candidate=$(gh api user --jq .login 2>/dev/null || true)
  fi

  if [ -n "$candidate" ] && is_github_username "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

if github_user=$(resolve_github_user); then
  user_root=$github_root/$github_user
  mkdir -p "$user_root"
  echo "  ✓ $user_root"
else
  echo "  → GitHub username not resolved yet"
  echo "  Set GITHUB_USER in ~/.localrc or: git config --global github.user <handle>"
fi

echo "✓ Workspace layout ready"
