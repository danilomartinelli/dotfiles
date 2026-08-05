#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-installer-preamble-tests

PREAMBLE=$REPOSITORY_ROOT/_scripts/installer-preamble.sh
LINK_CONFIG=$REPOSITORY_ROOT/_scripts/link-config

make_checkout() {
  local checkout
  checkout=$(scenario_tmpdir checkout)

  mkdir -p \
    "$checkout/_scripts" \
    "$checkout/sample" \
    "$checkout/home"

  cp "$PREAMBLE" "$checkout/_scripts/installer-preamble.sh"
  cp "$LINK_CONFIG" "$checkout/_scripts/link-config"
  chmod +x "$checkout/_scripts/link-config"

  printf '%s\n' "$checkout"
}

write_synthetic_installer() {
  local installer=$1
  shift

  scenario_write_executable "$installer" <<EOF
#!/bin/sh
set -eu
# shellcheck disable=SC1091
. "\$(CDPATH='' cd -P -- "\$(dirname -- "\$0")/../_scripts" && pwd)/installer-preamble.sh"
$*
EOF
}

test_resolves_topic_dir_and_checkout_root() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'printf "%s\n" "$TOPIC_DIR" >"$HOME/topic_dir"
printf "%s\n" "$DOTFILES_ROOT" >"$HOME/dotfiles_root"'

  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  assert_equal "$checkout/sample" "$(cat "$home/topic_dir")" 'TOPIC_DIR'
  assert_equal "$checkout" "$(cat "$home/dotfiles_root")" 'DOTFILES_ROOT'
}

test_darwin_guard_skips_on_non_darwin() {
  local checkout home fake_bin

  checkout=$(make_checkout)
  home=$checkout/home
  fake_bin=$home/fake-bin
  mkdir -p "$fake_bin"
  scenario_write_executable "$fake_bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' Linux
EOF

  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_require_darwin
printf "ran\n" >"$HOME/ran"'

  scenario_capture "$home" env HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
    "$checkout/sample/install.sh"
  [[ ! -e $home/ran ]]
}

test_link_config_wrapper_delegates() {
  local checkout home source target

  checkout=$(make_checkout)
  home=$checkout/home
  source=$checkout/sample/tracked.conf
  target=$home/.config/app/config
  printf 'tracked\n' >"$source"
  mkdir -p "$(dirname "$target")"

  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_link_config --label "app config" \
  "$TOPIC_DIR/tracked.conf" "$HOME/.config/app/config"'

  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  assert_equal "$source" "$(readlink "$target")" 'linked target'
  assert_contains "$home/stdout.log" 'app config linked'
}

test_output_helpers() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_banner "setting up sample"
installer_success "sample configured"
installer_note "customize locally"
installer_warn "something optional"'

  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  assert_contains "$home/stdout.log" '› setting up sample'
  assert_contains "$home/stdout.log" '✓ sample configured'
  assert_contains "$home/stdout.log" '  → customize locally'
  assert_contains "$home/stderr.log" 'Warning: something optional'
  assert_not_contains "$home/stdout.log" 'Warning: something optional'
}

test_safe_under_set_eu() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_banner "eu safe"
installer_success "done"'

  # Installer already uses set -eu via write_synthetic_installer.
  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  assert_contains "$home/stdout.log" '› eu safe'
}

test_preamble_not_in_topic_catalog() {
  local checkout catalog_output

  checkout=$(make_checkout)
  scenario_write_executable "$checkout/sample/install.sh" <<'EOF'
#!/bin/sh
exit 0
EOF

  catalog_output=$("$REPOSITORY_ROOT/_scripts/topic-catalog" "$checkout") || return 1
  if printf '%s\n' "$catalog_output" | grep -Fq "$checkout/_scripts/installer-preamble.sh"; then
    scenario_fail 'preamble appeared in topic catalog'
  fi
  if ! printf '%s\n' "$catalog_output" | grep -Fq "$checkout/sample/install.sh"; then
    scenario_fail 'expected sample installer in catalog'
  fi
}

scenario_run 'resolves TOPIC_DIR and DOTFILES_ROOT from the installer' \
  test_resolves_topic_dir_and_checkout_root
scenario_run 'Darwin guard exits successfully on non-Darwin' \
  test_darwin_guard_skips_on_non_darwin
scenario_run 'link-config wrapper delegates labels and policies' \
  test_link_config_wrapper_delegates
scenario_run 'output helpers emit the inner vocabulary' test_output_helpers
scenario_run 'sourcing is safe under set -eu' test_safe_under_set_eu
scenario_run 'preamble is excluded from topic discovery' \
  test_preamble_not_in_topic_catalog
scenario_finish
