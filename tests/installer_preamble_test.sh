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
    "$checkout/other" \
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

# Mirrors an installer whose $0 is wrong (bash via BASH_SOURCE), but keeps the
# source path itself resolved from $0 so the assertions isolate the preamble.
write_anchored_installer() {
  local installer=$1
  local anchor=$2
  shift 2

  scenario_write_executable "$installer" <<EOF
#!/bin/sh
set -eu
INSTALLER_ANCHOR=$anchor
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

test_require_command_passes_when_present() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_require_command sh
printf "ran\n" >"$HOME/ran"'

  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  [[ -e $home/ran ]] || scenario_fail 'installer body did not run'
}

test_require_command_fails_with_formula_hint() {
  local checkout home status

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_require_command sample-missing-tool
printf "ran\n" >"$HOME/ran"'

  status=0
  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh" || status=$?
  assert_equal 1 "$status" 'exit status for a missing command'
  assert_contains "$home/stderr.log" \
    'Error: sample-missing-tool is required but not installed'
  # The Homebrew formula defaults to the command name.
  assert_contains "$home/stderr.log" \
    '  → Install with: brew install sample-missing-tool'
  [[ ! -e $home/ran ]] || scenario_fail 'installer body ran despite a missing command'
}

test_require_command_accepts_formula_override() {
  local checkout home status

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_require_command sample-missing-tool sample-formula'

  status=0
  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh" || status=$?
  assert_equal 1 "$status" 'exit status for a missing command'
  assert_contains "$home/stderr.log" '  → Install with: brew install sample-formula'
}

test_require_app_skips_with_cask_hint() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_require_app Sample sample-cask "$HOME/Applications/Sample.app"
printf "ran\n" >"$HOME/ran"'

  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  assert_contains "$home/stderr.log" 'Warning: Sample not installed yet; skipping'
  assert_contains "$home/stderr.log" '  → Install with: brew install --cask sample-cask'
  [[ ! -e $home/ran ]] || scenario_fail 'installer body ran despite a missing app'
}

test_require_app_sets_first_existing_candidate() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  mkdir -p "$home/Applications/Sample 2.app" "$home/Applications/Sample.app"
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_require_app Sample sample-cask \
  "$HOME/Applications/Sample 3.app" \
  "$HOME/Applications/Sample 2.app" \
  "$HOME/Applications/Sample.app"
printf "%s\n" "$INSTALLER_APP" >"$HOME/installer_app"'

  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  assert_equal "$home/Applications/Sample 2.app" "$(cat "$home/installer_app")" \
    'INSTALLER_APP'
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
installer_warn "something optional"
installer_error "something required"
installer_hint "Install with: brew install sample"'

  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  assert_contains "$home/stdout.log" '› setting up sample'
  assert_contains "$home/stdout.log" '✓ sample configured'
  assert_contains "$home/stdout.log" '  → customize locally'
  assert_contains "$home/stderr.log" 'Warning: something optional'
  assert_not_contains "$home/stdout.log" 'Warning: something optional'
  assert_contains "$home/stderr.log" 'Error: something required'
  assert_not_contains "$home/stdout.log" 'Error: something required'
  # Hints continue the warning or error above them, so they stay on stderr.
  assert_contains "$home/stderr.log" '  → Install with: brew install sample'
  assert_not_contains "$home/stdout.log" 'Install with: brew install sample'
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

test_anchor_overrides_argv_zero() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_anchored_installer "$checkout/sample/install.sh" '$HOME/../other/install.sh' \
    'printf "%s\n" "$TOPIC_DIR" >"$HOME/topic_dir"
printf "%s\n" "$DOTFILES_ROOT" >"$HOME/dotfiles_root"'

  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  assert_equal "$checkout/other" "$(cat "$home/topic_dir")" 'anchored TOPIC_DIR'
  assert_equal "$checkout" "$(cat "$home/dotfiles_root")" 'anchored DOTFILES_ROOT'
}

test_anchor_is_consumed_by_the_preamble() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_anchored_installer "$checkout/sample/install.sh" '$HOME/../other/install.sh' \
    'printf "%s\n" "${INSTALLER_ANCHOR-unset}" >"$HOME/anchor_after"
# A second source must fall back to $0 rather than reuse the stale anchor.
# shellcheck disable=SC1091
. "$DOTFILES_ROOT/_scripts/installer-preamble.sh"
printf "%s\n" "$TOPIC_DIR" >"$HOME/topic_dir"'

  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  assert_equal 'unset' "$(cat "$home/anchor_after")" 'INSTALLER_ANCHOR after sourcing'
  assert_equal "$checkout/sample" "$(cat "$home/topic_dir")" 'TOPIC_DIR on re-source'
}

test_unresolvable_anchor_fails() {
  local checkout home status

  checkout=$(make_checkout)
  home=$checkout/home
  write_anchored_installer "$checkout/sample/install.sh" '$HOME/missing-topic/install.sh' \
    'printf "ran\n" >"$HOME/ran"'

  status=0
  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh" || status=$?
  assert_equal 1 "$status" 'exit status for unresolvable anchor'
  assert_contains "$home/stderr.log" 'installer-preamble: cannot resolve topic directory'
  [[ ! -e $home/ran ]] || scenario_fail 'installer body ran despite a bad anchor'
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
scenario_run 'require_command passes when the command exists' \
  test_require_command_passes_when_present
scenario_run 'require_command fails loudly with a formula hint' \
  test_require_command_fails_with_formula_hint
scenario_run 'require_command honors a formula override' \
  test_require_command_accepts_formula_override
scenario_run 'require_app skips cleanly with a cask hint' \
  test_require_app_skips_with_cask_hint
scenario_run 'require_app records the first existing candidate' \
  test_require_app_sets_first_existing_candidate
scenario_run 'link-config wrapper delegates labels and policies' \
  test_link_config_wrapper_delegates
scenario_run 'output helpers emit the inner vocabulary' test_output_helpers
scenario_run 'sourcing is safe under set -eu' test_safe_under_set_eu
scenario_run 'INSTALLER_ANCHOR overrides $0' test_anchor_overrides_argv_zero
scenario_run 'INSTALLER_ANCHOR does not leak past the preamble' \
  test_anchor_is_consumed_by_the_preamble
scenario_run 'unresolvable INSTALLER_ANCHOR fails loudly' test_unresolvable_anchor_fails
scenario_run 'preamble is excluded from topic discovery' \
  test_preamble_not_in_topic_catalog
scenario_finish
