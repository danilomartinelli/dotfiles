# Homelab access shortcuts. Reads HOMELAB_HOST (default: homelab) which
# matches the Tailscale MagicDNS hostname the server advertises after
# `tailscale up`. The deploy script reads HOMELAB_REPO_DIR (default: the
# clone path used by install.sh) to find the flake.

HOMELAB_HOST="${HOMELAB_HOST:-homelab}"
HOMELAB_REPO_DIR="${HOMELAB_REPO_DIR:-$HOME/Workspace/github.com/danilomartinelli/homelab}"

alias hl="ssh $HOMELAB_HOST"
alias hllog='ssh -t "$HOMELAB_HOST" sudo journalctl -u '\''*-homelab*'\'' -f'
alias hlup="$HOMELAB_REPO_DIR/scripts/deploy.sh $HOMELAB_HOST"
alias hldoctor="$HOMELAB_REPO_DIR/scripts/healthcheck.sh $HOMELAB_HOST"
alias hlbootstrap="$HOMELAB_REPO_DIR/scripts/bootstrap.sh"
