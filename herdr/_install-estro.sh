#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

app_dir=$(installer_config_dir herdr-app)
estro_dir=$TOPIC_DIR/estro
mkdir -p "$app_dir/mods"
stage=$(mktemp -d "$app_dir/.estro.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
trap 'exit 1' HUP INT TERM

# Herdr resolves mod assets inside its home and Better Config saves options
# there. Install real directories and preserve any existing mod by name.
for source in "$estro_dir"/mods/* "$TOPIC_DIR/skillshare/mods/skillshare"; do
  name=${source##*/}
  destination=$app_dir/mods/$name
  if [ -e "$destination" ] || [ -L "$destination" ]; then
    continue
  fi

  cp -R "$source" "$stage/$name"
  case "$name" in
    branch-pr) helper=herdr-pr ;;
    branch-issue) helper=herdr-linear ;;
    *) helper= ;;
  esac
  if [ -n "$helper" ]; then
    installer_require_command mise
    mkdir "$stage/$name/bin"
    GOWORK=off "$DOTFILES_ROOT/_scripts/mise-policy" "$DOTFILES_ROOT" run exec go -- \
      go -C "$estro_dir/helpers/$name" build -o "$stage/$name/bin/$helper" .
  fi
done

for source in "$stage"/*; do
  [ -d "$source" ] || continue
  mv -n "$source" "$app_dir/mods/"
done

installer_link_config --policy preserve-existing --label "Herdr Estro layout" \
  "$TOPIC_DIR/layouts/estro.json" "$app_dir/layouts/estro.json"

# Let Herdr create its version's default keys on first launch. Add Estro's
# layout-specific shortcuts when that file exists, giving existing keys priority.
keys=$app_dir/keys.json
if [ -f "$keys" ] && [ ! -L "$keys" ]; then
  installer_require_command jq
  cp -p "$keys" "$stage/keys.json"
  jq --slurpfile estro "$estro_dir/keys.json" '
    . as $existing
    | .["layout:estro"] = (
      ($estro[0]["layout:estro"] | with_entries(
        .key as $key | select($existing.global[$key] == null and $existing.terminal[$key] == null)
      )) + (.["layout:estro"] // {})
    )
  ' "$keys" >"$stage/keys.json"
  if ! cmp -s "$keys" "$stage/keys.json"; then
    mv "$stage/keys.json" "$keys"
  fi
fi
