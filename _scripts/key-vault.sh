# shellcheck shell=sh
# shellcheck disable=SC2034 # The commands sourcing this read what it sets.
#
# What key-backup and key-restore agree on: which keys there are, where each
# lives on this Mac and in Bitwarden, and that the vault must be unlocked.
#
# The keys are exactly the ones ssh-key-create and sops-key-create can create,
# under the names below. Each is one secure note, dotfiles/keys/<name>, whose
# text is the private key and whose `public` field is its public half.
#
# Sourced after _scripts/key-provisioning.sh, whose guards both commands use.
# Every variable here carries the _kv_ prefix or the key_vault_ one, for the
# reason that file gives: POSIX sh has no function locals.

key_vault_prefix=dotfiles/keys/
key_vault_names='ssh-default ssh-personal ssh-work age-default age-personal age-work'

# Set key_vault_private and key_vault_public for a key name, or return 1 for a
# name that is not one of the keys.
# Usage: key_vault_paths <name>
key_vault_paths() {
  case $1 in
    ssh-default) key_vault_private=$HOME/.ssh/id_ed25519 ;;
    ssh-personal) key_vault_private=$HOME/.ssh/id_ed25519_personal ;;
    ssh-work) key_vault_private=$HOME/.ssh/id_ed25519_work ;;
    age-default)
      key_vault_private=$HOME/.config/sops/age/keys.txt
      key_vault_public=$HOME/.config/sops/age/recipient.txt
      return 0
      ;;
    age-personal)
      key_vault_private=$HOME/.config/sops/age/keys_personal.txt
      key_vault_public=$HOME/.config/sops/age/recipient_personal.txt
      return 0
      ;;
    age-work)
      key_vault_private=$HOME/.config/sops/age/keys_work.txt
      key_vault_public=$HOME/.config/sops/age/recipient_work.txt
      return 0
      ;;
    *) return 1 ;;
  esac
  key_vault_public=$key_vault_private.pub
}

# Stop unless every named key is one of the keys.
# Usage: key_vault_check_names <program> <usage-function> [name...]
key_vault_check_names() {
  _kv_program=$1
  _kv_usage_fn=$2
  shift 2
  for _kv_name in "$@"; do
    key_vault_paths "$_kv_name" \
      || key_usage_error "$_kv_program" "$_kv_usage_fn" "unknown key: $_kv_name"
  done
}

# Stop unless Bitwarden's CLI and jq are present and the vault is unlocked,
# then refresh the vault from the server.
# Usage: key_vault_open <program>
key_vault_open() {
  key_require_generator "$1" bw 'brew install bitwarden-cli'
  key_require_generator "$1" jq 'brew install jq'

  _kv_status=$(bw status | jq -r .status) || {
    echo "$1: cannot read the Bitwarden vault status" >&2
    exit 1
  }
  if [ "$_kv_status" != unlocked ]; then
    echo "$1: the Bitwarden vault is $_kv_status" >&2
    # shellcheck disable=SC2016 # Printed for the person to run, not expanded here.
    echo '  unlock it with: export BW_SESSION=$(bw unlock --raw)' >&2
    exit 1
  fi
  bw sync >/dev/null || {
    echo "$1: could not refresh the vault from the server" >&2
    exit 1
  }
}
