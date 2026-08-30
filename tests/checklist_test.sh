#!/usr/bin/env bash
#
# The post-bootstrap checklist, driven through its own interface.
#
# The catalog seam DOTFILES_CHECKLIST_CATALOG is what makes this possible: the
# module reads a catalog this suite writes, so section routing and app opening
# are assertions about behaviour rather than greps of the module's source.

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-checklist-tests

CHECKLIST=$REPOSITORY_ROOT/_scripts/checklist
SHIPPED_CATALOG=$REPOSITORY_ROOT/_scripts/_checklist.tsv

# shellcheck source=_scripts/catalog.sh
# shellcheck disable=SC1091
source "$REPOSITORY_ROOT/_scripts/catalog.sh"

# One rule stays out of reach: which of a row's "|"-separated candidates
# open_app picks. It sits behind the interactive-terminal gate, and every way to
# satisfy that gate from a suite is worse than the gap — `script` copies
# terminal attributes from its own stdin and dies when the suite runs from a
# pipe, and pty.spawn does not return under the system Python 3.9. Which rows
# are opened at all is covered below; only the choice among candidate paths for
# one row is not.
#
# A fixture is a catalog plus a fake-bin holding the stubbed `open`. The module
# itself is never copied: the shipped file is the one under test.
new_fixture() {
  local fixture
  fixture=$(scenario_tmpdir fixture)
  mkdir -p "$fixture/fake-bin" "$fixture/home"
  cat >"$fixture/fake-bin/open" <<'EOF'
#!/bin/sh
printf 'open %s\n' "$*" >> "$OPEN_LOG"
EOF
  chmod +x "$fixture/fake-bin/open"
  : >"$fixture/open.log"
  printf '%s\n' "$fixture"
}

write_catalog() {
  local fixture=$1
  shift
  printf '%s\n' "$@" >"$fixture/catalog.tsv"
}

invoke_checklist() {
  local fixture=$1
  shift
  scenario_capture "$fixture" env \
    HOME="$fixture/home" \
    OPEN_LOG="$fixture/open.log" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    DOTFILES_ROOT="$REPOSITORY_ROOT" \
    DOTFILES_CHECKLIST_CATALOG="$fixture/catalog.tsv" \
    "$CHECKLIST" "$@"
}

# Print the lines a heading owns, up to the next heading. A row asserted this
# way cannot be satisfied by the same label printed under a different section.
checklist_section() {
  local log=$1
  local heading=$2

  awk -v heading="$heading" '
    index($0, heading) { inside = 1; next }
    inside && /^  \x1b\[1m/ { inside = 0 }
    inside { print }
  ' "$log"
}

assert_in_section() {
  local log=$1 heading=$2 needle=$3

  checklist_section "$log" "$heading" | grep -Fq -- "$needle" \
    || scenario_fail "Expected '$needle' under '$heading'"
}

assert_not_in_section() {
  local log=$1 heading=$2 needle=$3

  if checklist_section "$log" "$heading" | grep -Fq -- "$needle"; then
    scenario_fail "Did not expect '$needle' under '$heading'"
  fi
}

test_each_kind_prints_under_its_own_section() {
  local fixture
  fixture=$(new_fixture)
  mkdir -p "$fixture/Opened.app"

  write_catalog "$fixture" \
    "credential"$'\t'"-"$'\t'"a-key"$'\t'"create it by hand" \
    "app"$'\t'"$fixture/Opened.app"$'\t'"OpenedApp"$'\t'"finish the wizard" \
    "app"$'\t'"-"$'\t'"ManualApp"$'\t'"configure it in-app" \
    "shell"$'\t'"-"$'\t'"a-shell-step"$'\t'"run it once"

  invoke_checklist "$fixture"

  assert_in_section "$fixture/stdout.log" 'Credentials & keys' 'a-key'
  assert_in_section "$fixture/stdout.log" 'this opt-in command opens' 'OpenedApp'
  assert_in_section "$fixture/stdout.log" 'Apps requiring in-app setup' 'ManualApp'
  assert_in_section "$fixture/stdout.log" 'Shell' 'a-shell-step'

  # The app column decides membership, so a row can never be listed as opened
  # while being left closed.
  assert_not_in_section "$fixture/stdout.log" 'this opt-in command opens' 'ManualApp'
  assert_not_in_section "$fixture/stdout.log" 'Apps requiring in-app setup' 'OpenedApp'
}

test_an_empty_section_is_omitted() {
  local fixture
  fixture=$(new_fixture)

  write_catalog "$fixture" \
    "shell"$'\t'"-"$'\t'"only-step"$'\t'"run it once"

  invoke_checklist "$fixture"

  assert_contains "$fixture/stdout.log" 'only-step'
  assert_not_contains "$fixture/stdout.log" 'Credentials & keys'
  assert_not_contains "$fixture/stdout.log" 'Apps requiring in-app setup'
}

test_a_note_expands_the_checkout_root() {
  local fixture
  fixture=$(new_fixture)

  # The literal token belongs to the catalog, not to this shell. Expanding it
  # here would hand the module a path it never had to resolve.
  # shellcheck disable=SC2016
  write_catalog "$fixture" \
    "shell"$'\t'"-"$'\t'"a-step"$'\t''see $DOTFILES_ROOT/README.md'

  invoke_checklist "$fixture"

  assert_contains "$fixture/stdout.log" "see $REPOSITORY_ROOT/README.md"
  # shellcheck disable=SC2016
  assert_not_contains "$fixture/stdout.log" '$DOTFILES_ROOT'
}

test_an_incomplete_row_stops_the_checklist() {
  local fixture
  fixture=$(new_fixture)

  write_catalog "$fixture" \
    "shell"$'\t'"-"$'\t'"a-step"

  assert_fails 'incomplete row' invoke_checklist "$fixture"
  assert_contains "$fixture/stderr.log" 'invalid checklist row'
}

test_an_unknown_kind_stops_the_checklist() {
  local fixture
  fixture=$(new_fixture)

  write_catalog "$fixture" \
    "wishlist"$'\t'"-"$'\t'"a-step"$'\t'"run it once"

  assert_fails 'unknown kind' invoke_checklist "$fixture"
  assert_contains "$fixture/stderr.log" "unknown checklist kind 'wishlist'"
}

test_a_missing_catalog_stops_the_checklist() {
  local fixture
  fixture=$(new_fixture)

  assert_fails 'missing catalog' invoke_checklist "$fixture"
  assert_contains "$fixture/stderr.log" 'checklist catalog not found'
}

test_printing_never_opens_anything() {
  local fixture
  fixture=$(new_fixture)
  mkdir -p "$fixture/Opened.app"

  write_catalog "$fixture" \
    "app"$'\t'"$fixture/Opened.app"$'\t'"OpenedApp"$'\t'"finish the wizard"

  invoke_checklist "$fixture"

  assert_contains "$fixture/stdout.log" 'OpenedApp'
  assert_empty "$fixture/open.log"
}

test_opening_requires_an_interactive_terminal() {
  local fixture
  fixture=$(new_fixture)
  mkdir -p "$fixture/Opened.app"

  write_catalog "$fixture" \
    "app"$'\t'"$fixture/Opened.app"$'\t'"OpenedApp"$'\t'"finish the wizard"

  assert_fails 'non-interactive opening' invoke_checklist "$fixture" --open-apps
  assert_contains "$fixture/stderr.log" \
    'app checklist opening requires an interactive terminal'
  assert_empty "$fixture/open.log"
}

# The shipped catalog, read through the one reader. A second hand-written read
# loop here is what this suite exists to remove.
CATALOG_FAILURES=0

check_shipped_row() {
  local kind=$1 app=$2 label=$3 note=$4 candidate

  if [ -z "$app" ] || [ -z "$label" ] || [ -z "$note" ]; then
    scenario_fail "incomplete checklist row: $kind $label"
    CATALOG_FAILURES=$((CATALOG_FAILURES + 1))
    return 0
  fi

  case "$kind" in
    credential | app | shell) ;;
    *)
      scenario_fail "unknown checklist kind '$kind' for $label"
      CATALOG_FAILURES=$((CATALOG_FAILURES + 1))
      return 0
      ;;
  esac

  if [ "$kind" != app ] && [ "$app" != - ]; then
    scenario_fail "$kind row must not declare an app: $label"
    CATALOG_FAILURES=$((CATALOG_FAILURES + 1))
    return 0
  fi

  if [ "$app" != - ]; then
    while IFS= read -r candidate; do
      case "$candidate" in
        /*.app) ;;
        *)
          scenario_fail "checklist candidate is not an app path: $candidate"
          CATALOG_FAILURES=$((CATALOG_FAILURES + 1))
          ;;
      esac
    done <<<"${app//|/$'\n'}"
  fi
  return 0
}

test_the_shipped_catalog_is_well_formed() {
  CATALOG_FAILURES=0
  catalog_each_row "$SHIPPED_CATALOG" check_shipped_row
  [ "$CATALOG_FAILURES" -eq 0 ]
}

# The roles named in the catalog are the ones git/install.sh and sops/install.sh
# look for; naming any other tells a person to create keys those installers
# will never find.
test_the_shipped_catalog_names_the_key_roles_the_installers_expect() {
  assert_contains "$SHIPPED_CATALOG" 'ssh-key-create default'
  assert_contains "$SHIPPED_CATALOG" 'sops-key-create default'
  assert_contains "$REPOSITORY_ROOT/git/install.sh" 'ssh-key-create default'
  assert_contains "$REPOSITORY_ROOT/sops/install.sh" 'sops-key-create default'
}

test_the_shipped_catalog_prints_and_opens_nothing() {
  local fixture
  fixture=$(new_fixture)
  cp "$SHIPPED_CATALOG" "$fixture/catalog.tsv"

  invoke_checklist "$fixture"

  assert_contains "$fixture/stdout.log" 'Post-bootstrap checklist'
  assert_contains "$fixture/stdout.log" 'Credentials & keys'
  assert_contains "$fixture/stdout.log" 'Shell'
  assert_empty "$fixture/open.log"
}

scenario_run 'each kind prints under its own section' \
  test_each_kind_prints_under_its_own_section
scenario_run 'an empty section is omitted' test_an_empty_section_is_omitted
scenario_run 'a note expands the checkout root' test_a_note_expands_the_checkout_root
scenario_run 'an incomplete row stops the checklist' \
  test_an_incomplete_row_stops_the_checklist
scenario_run 'an unknown kind stops the checklist' \
  test_an_unknown_kind_stops_the_checklist
scenario_run 'a missing catalog stops the checklist' \
  test_a_missing_catalog_stops_the_checklist
scenario_run 'printing never opens anything' test_printing_never_opens_anything
scenario_run 'opening requires an interactive terminal' \
  test_opening_requires_an_interactive_terminal
scenario_run 'the shipped catalog is well formed' \
  test_the_shipped_catalog_is_well_formed
scenario_run 'the shipped catalog names the key roles the installers expect' \
  test_the_shipped_catalog_names_the_key_roles_the_installers_expect
scenario_run 'the shipped catalog prints every section and opens nothing' \
  test_the_shipped_catalog_prints_and_opens_nothing
scenario_finish
