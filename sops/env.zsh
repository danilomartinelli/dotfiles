# SOPS + age identity defaults.
# Private keys live in $XDG_CONFIG_HOME/sops/age/ and are never committed.

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt}"

if [[ -r ${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/recipient.txt ]]; then
  export SOPS_AGE_RECIPIENTS="${SOPS_AGE_RECIPIENTS:-$(<"${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/recipient.txt")}"
fi
