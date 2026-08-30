# SOPS + age identity defaults.
# Private keys live in ~/.config/sops/age/ and are never committed. That is
# not where sops looks by default on macOS, which is why SOPS_AGE_KEY_FILE
# below is load-bearing rather than a convenience.

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

if [[ -r $HOME/.config/sops/age/recipient.txt ]]; then
  # head -1 guards against trailing lines/CRLF producing an invalid recipient.
  export SOPS_AGE_RECIPIENTS="${SOPS_AGE_RECIPIENTS:-$(head -n1 "$HOME/.config/sops/age/recipient.txt" | tr -d '[:space:]')}"
fi
