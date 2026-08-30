# shellcheck shell=bash
#
# The progress vocabulary the setup orchestrators print in.
#
# setup, link-dotfiles, and checklist are one flow to the person watching it,
# so the glyphs, the colours, and the stream each level goes to belong in one
# place. Three files carried byte-identical copies before this one existed.
#
# This is deliberately not the installer vocabulary. A topic installer prints
# under a banner with `›`, `✓`, and `  →` from _scripts/installer-preamble.sh;
# these bracketed levels are the orchestrator reporting on whole phases. The
# two nest rather than compete, which is why unifying them further would make
# the output worse rather than better.

info() {
  printf '  [ \033[00;34m..\033[0m ] %s\n' "$1"
}

prompt() {
  printf '  [ \033[0;33m??\033[0m ] %s\n' "$1"
}

success() {
  printf '  [ \033[00;32mOK\033[0m ] %s\n' "$1"
}

warn() {
  printf '  [\033[0;33mWARN\033[0m] %s\n' "$1" >&2
}

# Report and stop. Every caller treats a failure here as fatal, so the exit
# belongs with the message rather than at each call site.
fail() {
  printf '  [\033[0;31mFAIL\033[0m] %s\n' "$1" >&2
  exit 1
}
