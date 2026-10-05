#!/bin/sh

set -eu

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

roots=$("$DOTFILES_ROOT/_scripts/trusted-roots") \
  || installer_fail "cannot resolve the trusted roots"
rendered=$TOPIC_DIR/trusted-roots.local.toml

{
  printf '# Rendered from _scripts/trusted-roots. Edits are replaced.\n\n'
  printf '[settings]\ntrusted_config_paths = [\n'
  printf '%s\n' "$roots" | while IFS= read -r root; do
    escaped=$(printf '%s' "$root" | sed 's/[\\"]/\\&/g')
    printf '  "%s",\n' "$escaped"
  done
  printf ']\n'
} >"$rendered.tmp"
mv "$rendered.tmp" "$rendered"

installer_link_config --label "Mise trusted roots" \
  "$rendered" "$(installer_config_dir mise)/conf.d/trusted-roots.toml"
