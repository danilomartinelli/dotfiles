#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin
installer_banner "setting up direnv configuration"

# The whitelist names this machine's trusted roots, so the file is rendered on
# every run rather than tracked, and a WORKSPACE moved in .localrc reaches it on
# the next one. `*local*` keeps it out of Git, as it does the generated Git
# identity.
RENDERED=$TOPIC_DIR/direnv.local.toml

roots=$("$DOTFILES_ROOT/_scripts/trusted-roots") \
  || installer_fail "cannot resolve the trusted roots"

# A TOML basic string escapes only a backslash and a double quote.
toml_string() {
  printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"]/\\&/g')"
}

{
  printf '# Rendered by direnv/install.sh from _scripts/trusted-roots. Edits are replaced.\n\n'
  printf '[global]\n'
  printf '# A .env loads the way an .envrc does; an .envrc wins where both exist.\n'
  printf 'load_dotenv = true\n\n'
  printf '[whitelist]\n'
  printf 'prefix = [\n'
  printf '%s\n' "$roots" | while IFS= read -r root; do
    printf '  %s,\n' "$(toml_string "$root")"
  done
  printf ']\n'
} >"$RENDERED.tmp"
mv "$RENDERED.tmp" "$RENDERED"

CONFIG_DIR=$(installer_config_dir direnv)
mkdir -p "$CONFIG_DIR"
installer_link_config --label "direnv config" "$RENDERED" "$CONFIG_DIR/direnv.toml"

installer_success "direnv configured"
