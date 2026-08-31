# shellcheck shell=sh
#
# The progress vocabulary a topic installer and the modules it calls print in.
#
# This is the installer half of what _scripts/output.sh did for the setup
# orchestrators, and it exists for the same reason: three modules outside the
# preamble carried their own copies of these glyphs, so a change to one voice
# reached only one of them.
#
# Two levels, and the difference between them is load-bearing. A phase result
# sits flush against the banner that opened it; an item inside that phase is
# indented under it. A run reads as
#
#   › setting up ssh configuration
#     ✓ ~/.ssh/config linked
#   ✓ ssh configuration complete
#
# The linker's line is an item and the installer's is the phase, which is why
# installer_item exists rather than every caller reaching for installer_success
# and losing the nesting. link-config, set-defaults.sh, and set-hostname.sh each
# invented the indented form independently; the preamble never had it.

installer_banner() {
  printf '› %s\n' "$*"
}

installer_success() {
  printf '✓ %s\n' "$*"
}

# One step inside the phase a banner opened, nested under it.
installer_item() {
  printf '  ✓ %s\n' "$*"
}

installer_note() {
  printf '  → %s\n' "$*"
}

installer_warn() {
  printf 'Warning: %s\n' "$*" >&2
}

installer_error() {
  printf 'Error: %s\n' "$*" >&2
}

# Actionable follow-up for the warning or error just emitted, so the whole
# message stays on one stream. Use installer_note for stdout follow-ups.
installer_hint() {
  printf '  → %s\n' "$*" >&2
}
