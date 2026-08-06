# Close ControlMaster sessions politely (ssh -O exit per socket), then drop
# orphaned socket files. Never killall: other terminals may hold live sessions.
sshclean() {
  local socket closed=0
  for socket in "$HOME"/.ssh/sockets/*(N); do
    if ssh -O exit -o ControlPath="$socket" _unused_host 2>/dev/null; then
      ((closed++))
    else
      rm -f "$socket"
    fi
  done
  print "=> SSH control sockets cleaned ($closed closed politely)."
}

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
