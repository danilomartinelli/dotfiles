#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "configuring homelab access"

# Topic-level knobs. Set these in ~/.localrc to match the Tailscale
# MagicDNS hostname (or fallback IP) of the VPS, or export them in the
# current shell before running the dot command.
HOMELAB_REPO_DIR="${HOMELAB_REPO_DIR:-$HOME/Workspace/github.com/danilomartinelli/homelab}"
HOMELAB_SSH_KEY="${HOMELAB_SSH_KEY:-$HOME/.ssh/id_ed25519}"

# 1. Clone the homelab flake repo if it's not already present. This is the
#    same repo the VPS itself reads from, so the laptop and server stay in
#    lockstep when you commit locally and deploy via scripts/deploy.sh.
if [ ! -d "$HOMELAB_REPO_DIR/.git" ]; then
  mkdir -p "$(dirname "$HOMELAB_REPO_DIR")"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    installer_note "Cloning homelab via gh"
    gh repo clone danilomartinelli/homelab "$HOMELAB_REPO_DIR"
  elif command -v git >/dev/null 2>&1; then
    installer_note "Cloning homelab via git"
    git clone "https://github.com/danilomartinelli/homelab.git" "$HOMELAB_REPO_DIR"
  else
    installer_warn "no git or gh available; skipping clone of homelab repo"
  fi
else
  installer_success "homelab repo present at $HOMELAB_REPO_DIR"
fi

# 2. Make sure an SSH key exists for talking to the VPS. Reuse the existing
#    personal key if present; otherwise create one. Refuse to overwrite.
if [ ! -e "$HOMELAB_SSH_KEY" ]; then
  if command -v ssh-keygen >/dev/null 2>&1; then
    ssh-keygen -t ed25519 -N "" -C "homelab-$(hostname -s)" -f "$HOMELAB_SSH_KEY"
    installer_success "Generated $HOMELAB_SSH_KEY"
  else
    installer_warn "ssh-keygen not available; create $HOMELAB_SSH_KEY manually"
  fi
else
  installer_note "homelab SSH key already at $HOMELAB_SSH_KEY"
fi

# 3. Append a config_local entry for the homelab host if it's missing. The
#    ssh/install.sh contract preserves config_local and treats it as
#    machine-private state. We only add the block when the hostname is
#    already known to the user (via $HOMELAB_HOST).
HOMELAB_HOST="${HOMELAB_HOST:-homelab}"
SSH_CONFIG_LOCAL="$HOME/.ssh/config_local"
if [ -n "$HOMELAB_HOST" ] && ! grep -qE "^Host\s+$HOMELAB_HOST(\s|$)" "$SSH_CONFIG_LOCAL" 2>/dev/null; then
  {
    printf '\n# Managed by homelab/install.sh\n'
    printf 'Host %s\n' "$HOMELAB_HOST"
    printf '  HostName %s\n' "$HOMELAB_HOST"
    printf '  User admin\n'
    printf '  IdentityFile %s\n' "$HOMELAB_SSH_KEY"
    printf '  UpdateHostKeys yes\n'
    printf '  StrictHostKeyChecking accept-new\n'
  } >>"$SSH_CONFIG_LOCAL"
  chmod 600 "$SSH_CONFIG_LOCAL"
  installer_success "Added $HOMELAB_HOST to $SSH_CONFIG_LOCAL"
else
  installer_note "$HOMELAB_HOST already in $SSH_CONFIG_LOCAL"
fi

# 4. Verify the local nix toolchain is present (the deploy script runs
#    nix commands on the remote, not locally; this is a soft check).
if command -v nix >/dev/null 2>&1; then
  installer_success "nix available locally (optional)"
else
  installer_note "nix not installed locally — fine, the server runs nix; deploy.sh uses ssh"
fi

installer_note "Run 'hl' to ssh in, 'hlup' to redeploy, 'hldoctor' for a health check"
installer_success "homelab configured"
