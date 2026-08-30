#!/usr/bin/env bash
# shellcheck disable=SC2016 # Fixture commands and labels intentionally remain literal.

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/stubs.sh
source "$TEST_DIR/_support/stubs.sh"
scenario_init dotfiles-installer-preamble-tests

PREAMBLE=$REPOSITORY_ROOT/_scripts/installer-preamble.sh
LINK_CONFIG=$REPOSITORY_ROOT/_scripts/link-config
CATALOG_READER=$REPOSITORY_ROOT/_scripts/catalog.sh

make_checkout() {
  local checkout
  checkout=$(scenario_tmpdir checkout)

  mkdir -p \
    "$checkout/_scripts" \
    "$checkout/sample" \
    "$checkout/other" \
    "$checkout/home"

  cp "$PREAMBLE" "$checkout/_scripts/installer-preamble.sh"
  cp "$CATALOG_READER" "$checkout/_scripts/catalog.sh"
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
  stub_uname "$fake_bin"

  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_require_darwin
printf "ran\n" >"$HOME/ran"'

  scenario_capture "$home" env HOME="$home" FAKE_UNAME=Linux \
    PATH="$fake_bin:/usr/bin:/bin" \
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

test_optional_app_skips_with_cask_hint() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_optional_app Sample sample-cask "$HOME/Applications/Sample.app"
printf "ran\n" >"$HOME/ran"'

  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  assert_contains "$home/stderr.log" 'Warning: Sample not installed yet; skipping'
  assert_contains "$home/stderr.log" '  → Install with: brew install --cask sample-cask'
  [[ ! -e $home/ran ]] || scenario_fail 'installer body ran despite a missing app'
}

test_optional_app_sets_first_existing_candidate() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  mkdir -p "$home/Applications/Sample 2.app" "$home/Applications/Sample.app"
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_optional_app Sample sample-cask \
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

test_optional_command_passes_when_present() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_optional_command sh "sh is required for the sample step"
printf "ran\n" >"$HOME/ran"'

  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  [[ -e $home/ran ]] || scenario_fail 'installer body did not run'
}

test_optional_command_skips_with_reason_and_hint() {
  local checkout home status

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_optional_command sample-missing-tool "sample-missing-tool sets the sample default"
printf "ran\n" >"$HOME/ran"'

  status=0
  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh" || status=$?
  # Skipping an optional dependency is a success, unlike a required one.
  assert_equal 0 "$status" 'exit status for a missing optional command'
  assert_contains "$home/stderr.log" \
    'Warning: sample-missing-tool sets the sample default'
  assert_contains "$home/stderr.log" \
    '  → Install with: brew install sample-missing-tool'
  [[ ! -e $home/ran ]] || scenario_fail 'installer body ran despite a missing optional command'
}

test_optional_command_accepts_formula_override() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_optional_command sample-missing-tool "sample reason" sample-formula'

  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh"
  assert_contains "$home/stderr.log" '  → Install with: brew install sample-formula'
}

# Body shared by the run-once scenarios: gate, do the work, record the marker.
write_run_once_installer() {
  write_synthetic_installer "$1" \
    'installer_skip_if_applied sample-step "sample layout" "sample configured"
printf "ran\n" >"$HOME/ran"
installer_mark_applied sample-step
installer_success "sample configured"'
}

test_config_dir_resolves_under_home() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_config_dir zed >"$HOME/config_dir"'

  scenario_capture "$home" env -u XDG_CONFIG_HOME HOME="$home" \
    "$checkout/sample/install.sh"
  assert_equal "$home/.config/zed" "$(cat "$home/config_dir")" \
    'resolved tool config directory'
  # The resolver only resolves. Creating the directory stays the caller's own
  # line, so sops can keep its umask above the mkdir that needs it.
  [[ ! -e $home/.config ]] \
    || scenario_fail 'config directory resolver created a directory'
}

test_config_dir_ignores_xdg_config_home() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_config_dir zed >"$HOME/config_dir"'

  scenario_capture "$home" env HOME="$home" XDG_CONFIG_HOME="$checkout/xdg" \
    "$checkout/sample/install.sh"
  # Deliberate, not an oversight: honouring XDG_CONFIG_HOME is each tool's fact
  # to state, and Zed hardcodes ~/.config/zed on macOS. This assertion is what
  # keeps docs/adr/0003-tool-config-directories-are-not-xdg-derived.md true.
  assert_equal "$home/.config/zed" "$(cat "$home/config_dir")" \
    'tool config directory with XDG_CONFIG_HOME set'
  [[ ! -e $checkout/xdg ]] \
    || scenario_fail 'resolver wrote below XDG_CONFIG_HOME'
}

test_skip_if_applied_runs_the_step_without_a_marker() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_run_once_installer "$checkout/sample/install.sh"

  scenario_capture "$home" env -u DOTFILES_RESET HOME="$home" \
    XDG_STATE_HOME="$home/state" "$checkout/sample/install.sh"
  [[ -e $home/ran ]] || scenario_fail 'run-once step did not run on a clean state directory'
  [[ -f $home/state/dotfiles/sample-step-applied ]] \
    || scenario_fail 'run-once marker not recorded'
  # DOTFILES_RESET is unset here, so the gate must not trip set -u.
  assert_not_contains "$home/stderr.log" 'unbound variable'
}

test_skip_if_applied_skips_when_the_marker_exists() {
  local checkout home status

  checkout=$(make_checkout)
  home=$checkout/home
  mkdir -p "$home/state/dotfiles"
  touch "$home/state/dotfiles/sample-step-applied"
  write_run_once_installer "$checkout/sample/install.sh"

  status=0
  scenario_capture "$home" env -u DOTFILES_RESET HOME="$home" \
    XDG_STATE_HOME="$home/state" "$checkout/sample/install.sh" || status=$?
  assert_equal 0 "$status" 'exit status for an already-applied run-once step'
  assert_contains "$home/stdout.log" \
    '  → sample layout already applied; run DOTFILES_RESET=sample-step dot to reapply'
  # The gate owns the closing line, because the caller cannot print after it.
  assert_contains "$home/stdout.log" '✓ sample configured'
  assert_count "$home/stdout.log" '✓ sample configured' 1
  [[ ! -e $home/ran ]] || scenario_fail 'run-once step ran despite its marker'
}

test_skip_if_applied_reset_re_arms_the_step() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  mkdir -p "$home/state/dotfiles"
  touch "$home/state/dotfiles/sample-step-applied"
  write_run_once_installer "$checkout/sample/install.sh"

  scenario_capture "$home" env HOME="$home" XDG_STATE_HOME="$home/state" \
    DOTFILES_RESET='other-step sample-step' "$checkout/sample/install.sh"
  [[ -e $home/ran ]] || scenario_fail 'DOTFILES_RESET did not re-arm the named step'
}

test_skip_if_applied_reset_all_re_arms_every_step() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  mkdir -p "$home/state/dotfiles"
  touch "$home/state/dotfiles/sample-step-applied"
  write_run_once_installer "$checkout/sample/install.sh"

  scenario_capture "$home" env HOME="$home" XDG_STATE_HOME="$home/state" \
    DOTFILES_RESET=all "$checkout/sample/install.sh"
  [[ -e $home/ran ]] || scenario_fail 'DOTFILES_RESET=all did not re-arm the step'
}

test_skip_if_applied_reset_matches_whole_keys_only() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  mkdir -p "$home/state/dotfiles"
  touch "$home/state/dotfiles/sample-step-applied"
  write_run_once_installer "$checkout/sample/install.sh"

  # A longer key that merely contains this one must not re-arm it.
  scenario_capture "$home" env HOME="$home" XDG_STATE_HOME="$home/state" \
    DOTFILES_RESET='sample-step-extra' "$checkout/sample/install.sh"
  [[ ! -e $home/ran ]] || scenario_fail 'a partial key match re-armed the step'
}

test_mark_applied_falls_back_to_local_state() {
  local checkout home

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_mark_applied sample-step'

  scenario_capture "$home" env -u XDG_STATE_HOME HOME="$home" \
    "$checkout/sample/install.sh"
  [[ -f $home/.local/state/dotfiles/sample-step-applied ]] \
    || scenario_fail 'marker not created under the default state directory'
}

test_fail_reports_and_exits() {
  local checkout home status

  checkout=$(make_checkout)
  home=$checkout/home
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_fail "sample source not found: /nowhere"
printf "ran\n" >"$HOME/ran"'

  status=0
  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh" || status=$?
  assert_equal 1 "$status" 'exit status for installer_fail'
  assert_contains "$home/stderr.log" 'Error: sample source not found: /nowhere'
  assert_not_contains "$home/stdout.log" 'sample source not found'
  [[ ! -e $home/ran ]] || scenario_fail 'installer body ran after installer_fail'
}

test_fail_exits_from_inside_a_read_loop() {
  local checkout home status

  checkout=$(make_checkout)
  home=$checkout/home
  # opencode/install.sh calls installer_fail from a `while read ... done 3<file`
  # loop. That is a redirect rather than a pipeline, so exit must end the whole
  # installer instead of one iteration.
  write_synthetic_installer "$checkout/sample/install.sh" \
    'printf "%s\n" first second third >"$HOME/rows"
while read -r row <&3; do
  if [ "$row" = second ]; then
    installer_fail "invalid sample row: $row"
  fi
  printf "%s\n" "$row" >>"$HOME/seen"
done 3<"$HOME/rows"
printf "ran\n" >"$HOME/ran"'

  status=0
  scenario_capture "$home" env HOME="$home" "$checkout/sample/install.sh" || status=$?
  assert_equal 1 "$status" 'exit status for installer_fail inside a read loop'
  assert_contains "$home/stderr.log" 'Error: invalid sample row: second'
  assert_equal 'first' "$(cat "$home/seen")" 'rows handled before the failure'
  [[ ! -e $home/ran ]] || scenario_fail 'installer continued past a failing row'
}

# The catalog lives beside the installer, so a fixture topic dir is the whole
# setup: no path override exists, by design.
write_association_fixture() {
  local checkout=$1
  local catalog=$2
  local fake_bin=$checkout/home/fake-bin

  mkdir -p "$fake_bin"
  stub_duti "$fake_bin"

  printf '%s' "$catalog" >"$checkout/sample/_associations.tsv"
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_apply_associations Sample com.example.sample "sample associations set"'
}

write_claim_fixture() {
  local checkout=$1

  write_association_fixture "$checkout" "$(printf '%b\n' '.md\teditor\treport\t-')"
  write_synthetic_installer "$checkout/sample/install.sh" \
    'installer_claim_file_types Sample com.example.sample "sample associations set"'
}

invoke_claim() {
  local checkout=$1
  shift
  scenario_capture "$checkout/home" env \
    HOME="$checkout/home" \
    XDG_STATE_HOME="$checkout/home/state" \
    PATH="$checkout/home/fake-bin:/usr/bin:/bin" \
    "$@" \
    "$checkout/sample/install.sh"
}

invoke_associations() {
  local checkout=$1
  scenario_capture "$checkout/home" env \
    PATH="$checkout/home/fake-bin:/usr/bin:/bin" \
    "$checkout/sample/install.sh"
}

test_associations_apply_every_row_with_its_role() {
  local checkout
  checkout=$(make_checkout)
  write_association_fixture "$checkout" "$(printf '%b\n' \
    '# comment line ignored' \
    '' \
    '.md\teditor\treport\t-' \
    'public.zip-archive\tviewer\treport\t.zip' \
    'com.adobe.pdf\teditor\tignore\t-')"

  invoke_associations "$checkout"

  assert_count "$checkout/home/events.log" 'duti -s com.example.sample' 3
  assert_contains "$checkout/home/events.log" '.md editor'
  assert_contains "$checkout/home/events.log" 'public.zip-archive viewer'
  assert_contains "$checkout/home/events.log" 'com.adobe.pdf editor'
  assert_before "$checkout/home/events.log" '.md editor' 'public.zip-archive viewer'
  assert_contains "$checkout/home/stdout.log" '✓ sample associations set'
  assert_not_contains "$checkout/home/stderr.log" 'Warning:'
}

test_associations_name_a_reported_failure_by_label() {
  local checkout
  checkout=$(make_checkout)
  write_association_fixture "$checkout" "$(printf '%b\n' \
    'public.zip-archive\tviewer\treport\t.zip' \
    '.md\teditor\treport\t-')"

  export FAIL_DUTI='public.zip-archive'
  invoke_associations "$checkout"
  unset FAIL_DUTI

  # The label column carries the human name; a "-" falls back to the identifier.
  assert_contains "$checkout/home/stderr.log" \
    'Warning: Failed to set Sample as default for .zip'
  assert_contains "$checkout/home/stderr.log" \
    'Warning: Some Sample file associations could not be configured (1 failed)'
  assert_not_contains "$checkout/home/stdout.log" 'sample associations set'
}

test_associations_count_every_reported_failure() {
  local checkout
  checkout=$(make_checkout)
  write_association_fixture "$checkout" "$(printf '%b\n' \
    '.md\teditor\treport\t-' \
    '.rst\teditor\treport\t-' \
    '.txt\teditor\treport\t-')"

  export FAIL_DUTI='.md .rst'
  invoke_associations "$checkout"
  unset FAIL_DUTI

  # A count of 2 is what proves the loop does not run in a subshell, which is
  # why the catalog is read by redirection rather than through a pipe.
  assert_contains "$checkout/home/stderr.log" \
    'Warning: Some Sample file associations could not be configured (2 failed)'
  assert_contains "$checkout/home/stderr.log" 'default for .md'
  assert_contains "$checkout/home/stderr.log" 'default for .rst'
}

test_associations_swallow_a_best_effort_failure() {
  local checkout status
  checkout=$(make_checkout)
  write_association_fixture "$checkout" "$(printf '%b\n' \
    'public.source-code\teditor\tignore\t-' \
    '.md\teditor\treport\t-')"

  export FAIL_DUTI='public.source-code'
  status=0
  invoke_associations "$checkout" || status=$?
  unset FAIL_DUTI

  # Best-effort rows keep running under set -e and never reach the count.
  assert_equal 0 "$status" 'exit status when only a best-effort row fails'
  assert_contains "$checkout/home/events.log" '.md editor'
  assert_not_contains "$checkout/home/stderr.log" 'public.source-code'
  assert_contains "$checkout/home/stdout.log" '✓ sample associations set'
}

test_associations_fail_without_a_catalog() {
  local checkout status
  checkout=$(make_checkout)
  write_association_fixture "$checkout" "$(printf '%b\n' '.md\teditor\treport\t-')"
  rm "$checkout/sample/_associations.tsv"

  status=0
  invoke_associations "$checkout" || status=$?
  assert_equal 1 "$status" 'exit status for a missing association catalog'
  assert_contains "$checkout/home/stderr.log" 'Error: association catalog not readable'
  assert_not_contains "$checkout/home/stdout.log" 'sample associations set'
}

test_associations_fail_on_an_unknown_failure_mode() {
  local checkout status
  checkout=$(make_checkout)
  write_association_fixture "$checkout" "$(printf '%b\n' '.md\teditor\tigore\t-')"

  status=0
  invoke_associations "$checkout" || status=$?
  # Defaulting a typo either way would decide silently whether a failure is
  # heard, so an unknown mode is a catalog bug rather than a tolerated value.
  assert_equal 1 "$status" 'exit status for an unknown failure mode'
  assert_contains "$checkout/home/stderr.log" "Error: unknown failure mode 'igore' for .md"
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

# The run-once key is derived from the topic directory, which is what stops a
# topic gating on one key and marking another.
test_claim_derives_its_key_from_the_topic() {
  local checkout
  checkout=$(make_checkout)
  write_claim_fixture "$checkout"

  invoke_claim "$checkout"
  [[ -f $checkout/home/state/dotfiles/sample-associations-applied ]] \
    || scenario_fail 'claim did not record a marker keyed by the topic'
}

test_claim_applies_once_and_reports_the_marker() {
  local checkout
  checkout=$(make_checkout)
  write_claim_fixture "$checkout"

  invoke_claim "$checkout"
  assert_contains "$checkout/home/stdout.log" '✓ sample associations set'
  assert_contains "$checkout/home/stdout.log" '✓ Sample configured'

  # scenario_capture starts a fresh event log per run, so an empty one here is
  # the second run reasserting nothing.
  invoke_claim "$checkout"
  assert_not_contains "$checkout/home/events.log" 'duti -s'
  assert_contains "$checkout/home/stdout.log" \
    'file associations already applied; run DOTFILES_RESET=sample-associations dot to reapply'
  assert_contains "$checkout/home/stdout.log" '✓ Sample configured'
}

test_claim_reset_re_arms_the_step() {
  local checkout
  checkout=$(make_checkout)
  write_claim_fixture "$checkout"

  invoke_claim "$checkout"
  invoke_claim "$checkout" DOTFILES_RESET=sample-associations
  assert_contains "$checkout/home/events.log" 'duti -s com.example.sample .md editor'
  assert_contains "$checkout/home/stdout.log" '✓ sample associations set'
}

# A machine with the app but without duti has applied nothing, so the step has
# to stay armed for the run that follows installing duti.
test_claim_without_duti_leaves_the_step_armed() {
  local checkout
  checkout=$(make_checkout)
  write_claim_fixture "$checkout"
  rm "$checkout/home/fake-bin/duti"

  invoke_claim "$checkout"
  assert_contains "$checkout/home/stderr.log" \
    'duti is required to set Sample as the default app for its declared file types'
  [[ ! -f $checkout/home/state/dotfiles/sample-associations-applied ]] \
    || scenario_fail 'a run without duti recorded the marker'
}

scenario_run 'claim derives its run-once key from the topic' \
  test_claim_derives_its_key_from_the_topic
scenario_run 'claim applies once and reports the marker' \
  test_claim_applies_once_and_reports_the_marker
scenario_run 'DOTFILES_RESET re-arms a claimed catalog' \
  test_claim_reset_re_arms_the_step
scenario_run 'a claim without duti leaves the step armed' \
  test_claim_without_duti_leaves_the_step_armed
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
scenario_run 'optional_app skips cleanly with a cask hint' \
  test_optional_app_skips_with_cask_hint
scenario_run 'optional_app records the first existing candidate' \
  test_optional_app_sets_first_existing_candidate
scenario_run 'optional_command passes when the command exists' \
  test_optional_command_passes_when_present
scenario_run 'optional_command skips successfully with a reason and hint' \
  test_optional_command_skips_with_reason_and_hint
scenario_run 'optional_command honors a formula override' \
  test_optional_command_accepts_formula_override
scenario_run 'config_dir resolves a tool directory under HOME without creating it' \
  test_config_dir_resolves_under_home
scenario_run 'config_dir ignores XDG_CONFIG_HOME' \
  test_config_dir_ignores_xdg_config_home
scenario_run 'run-once step applies without a marker and records one' \
  test_skip_if_applied_runs_the_step_without_a_marker
scenario_run 'run-once step skips once its marker exists' \
  test_skip_if_applied_skips_when_the_marker_exists
scenario_run 'DOTFILES_RESET re-arms a named run-once step' \
  test_skip_if_applied_reset_re_arms_the_step
scenario_run 'DOTFILES_RESET=all re-arms every run-once step' \
  test_skip_if_applied_reset_all_re_arms_every_step
scenario_run 'DOTFILES_RESET matches whole keys only' \
  test_skip_if_applied_reset_matches_whole_keys_only
scenario_run 'run-once markers fall back to ~/.local/state' \
  test_mark_applied_falls_back_to_local_state
scenario_run 'fail reports on stderr and exits 1' test_fail_reports_and_exits
scenario_run 'fail terminates the installer from inside a read loop' \
  test_fail_exits_from_inside_a_read_loop
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
scenario_run 'associations apply every catalog row with its own role' \
  test_associations_apply_every_row_with_its_role
scenario_run 'a reported association failure is named by its label' \
  test_associations_name_a_reported_failure_by_label
scenario_run 'every reported association failure reaches the count' \
  test_associations_count_every_reported_failure
scenario_run 'a best-effort association failure is neither named nor counted' \
  test_associations_swallow_a_best_effort_failure
scenario_run 'a missing association catalog fails loudly' \
  test_associations_fail_without_a_catalog
scenario_run 'an unknown association failure mode fails loudly' \
  test_associations_fail_on_an_unknown_failure_mode
scenario_finish
