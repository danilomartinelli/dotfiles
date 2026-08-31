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

# The row's value is the JSON literal the key holds, so it reaches jq as JSON
# rather than through a second parse. Expansion happens before that, on the
# declared text, which is why it no longer needs to ask what JSON type the value
# turned out to be: the old sub() ran on top-level strings only, so an
# object-valued row was silently never expanded at all.
#
# Because the substitution lands inside JSON source text rather than inside a
# decoded string, the checkout path is JSON-escaped first. APFS allows both `"`
# and `\` in a path component, and either one spliced in raw would produce a
# value jq cannot parse — the old sub() could not hit this because jq
# re-serialized the string it had already decoded.
DOTFILES_ROOT_JSON=$(jq -rn --arg root "$DOTFILES_ROOT" '$root | tojson[1:-1]')

collect_setting() {
  _setting_value=$(catalog_expand "$2" DOTFILES_ROOT "$DOTFILES_ROOT_JSON")
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
