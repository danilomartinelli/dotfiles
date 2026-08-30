#!/bin/sh

set -eu

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up OpenChamber"

installer_require_darwin
OPENCHAMBER_APP=${OPENCHAMBER_APP:-/Applications/OpenChamber.app}
installer_optional_app OpenChamber openchamber "$OPENCHAMBER_APP"
installer_require_command jq

config_dir=$(installer_config_dir openchamber)
settings=$config_dir/settings.json
catalog=$DOTFILES_ROOT/openchamber/_settings.tsv

mkdir -p "$config_dir"
[ -f "$settings" ] || printf '{}\n' >"$settings"

# Collect the catalog into one object first, then merge it in a single pass.
# Merging per row would rewrite settings.json once per row and could leave it
# half-applied if the run were interrupted midway.
owned='{}'

collect_setting() {
  _setting_value=$(printf '%s' "$2" | jq -c --arg root "$DOTFILES_ROOT" \
    'if type == "string" then sub("\\{\\{DOTFILES_ROOT\\}\\}"; $root) else . end')
  owned=$(printf '%s' "$owned" | jq -c --arg key "$1" --argjson value "$_setting_value" \
    '.[$key] = $value')
  unset _setting_value
  return 0
}

catalog_each_row "$catalog" collect_setting

# Shallow merge: every catalogued key is owned whole, so a stale subkey from a
# previous shape must not survive underneath it. Keys outside the catalog --
# the relay keys, security-scoped bookmarks, and session state -- are carried
# through untouched, which is why this file is merged rather than linked.
merged=$(jq -S -c --argjson owned "$owned" '. + $owned' "$settings")

if [ "$merged" = "$(jq -S -c . "$settings")" ]; then
  installer_note "OpenChamber settings already match the catalog"
else
  printf '%s\n' "$merged" | jq . >"$settings.tmp"
  mv "$settings.tmp" "$settings"
  installer_success "merged $(printf '%s' "$owned" | jq 'keys | length') tracked settings"
fi

if pgrep -f '/OpenChamber\.app/' >/dev/null 2>&1; then
  installer_warn "OpenChamber is running and rewrites this file when it quits"
  installer_hint "Quit and reopen OpenChamber so it reloads these settings"
fi

installer_success "OpenChamber configuration complete"
