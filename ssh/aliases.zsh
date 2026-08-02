alias sshclean='rm -f ~/.ssh/sockets/*; killall ssh 2>/dev/null; echo "SSH sockets limpos"'

# Copy the default public key, preferring Ed25519 with an RSA fallback.
pubkey() {
  local public_key="$HOME/.ssh/id_ed25519.pub"

  if [[ ! -f "$public_key" ]]; then
    public_key="$HOME/.ssh/id_rsa.pub"
  fi

  if [[ ! -f "$public_key" ]]; then
    print -u2 'No default SSH public key found.'
    return 1
  fi

  if ! command -v pbcopy >/dev/null 2>&1; then
    print -u2 'pbcopy is required to copy the public key.'
    return 1
  fi

  if ! pbcopy < "$public_key"; then
    print -u2 'Failed to copy the public key.'
    return 1
  fi

  print '=> Public key copied to pasteboard.'
}
