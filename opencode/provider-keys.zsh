# OpenCode reads its providers' API keys from its environment. They are not
# exported in any shell: this starts OpenCode with the keys of its own store,
# so nothing else started from the shell inherits them. Zed starts its OpenCode
# agent through the same command (zed/settings.json).
opencode() {
  with-provider-keys opencode -- opencode "$@"
}
