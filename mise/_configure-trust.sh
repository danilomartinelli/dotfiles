#!/bin/sh

set -eu

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

settings=$("$DOTFILES_ROOT/_scripts/mise-policy" "$DOTFILES_ROOT" trust) \
  || installer_fail "cannot prepare the trusted roots"
rendered=$TOPIC_DIR/trusted-roots.local.toml

printf '%s\n' "$settings" >"$rendered.tmp"
mv "$rendered.tmp" "$rendered"

installer_link_config --label "Mise trusted roots" \
  "$rendered" "$(installer_config_dir mise)/conf.d/trusted-roots.toml"
