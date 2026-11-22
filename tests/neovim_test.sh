#!/usr/bin/env bash
#
# Neovim as the editor every shell opens: what the topic links, and that the
# configuration still starts when its one plugin cannot be fetched.

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/stubs.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/stubs.sh"
# shellcheck source=tests/_support/fixture.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/fixture.sh"
scenario_init dotfiles-neovim-tests

test_the_topic_links_the_configuration_and_the_plugin_lock() {
  local fixture file
  fixture=$(installer_fixture)
  fixture_run "$fixture" -- "$REPOSITORY_ROOT/neovim/install.sh"

  for file in init.lua nvim-pack-lock.json; do
    assert_equal "$REPOSITORY_ROOT/neovim/$file" \
      "$(readlink "$fixture/home/.config/nvim/$file")" "source of $file"
  done
}

test_every_shell_and_git_open_neovim() {
  assert_contains "$REPOSITORY_ROOT/.commonrc" 'export EDITOR="nvim"'
  assert_contains "$REPOSITORY_ROOT/.commonrc" 'export VISUAL="nvim"'
  assert_equal nvim \
    "$(git config --file "$REPOSITORY_ROOT/git/gitconfig.symlink" core.editor)" \
    'core.editor'
}

# The lock names the plugin the configuration adds, at one full revision.
test_the_plugin_lock_pins_the_one_plugin() {
  jq -e '.plugins | keys == ["catppuccin"]
    and (.catppuccin.rev | test("^[0-9a-f]{40}$"))
    and .catppuccin.src == "https://github.com/catppuccin/nvim"' \
    "$REPOSITORY_ROOT/neovim/nvim-pack-lock.json" >/dev/null \
    || scenario_fail 'nvim-pack-lock.json must pin catppuccin to one revision'
  assert_contains "$REPOSITORY_ROOT/neovim/init.lua" "src = 'https://github.com/catppuccin/nvim'"
}

# Without git on PATH the plugin cannot be fetched, the way it cannot offline.
# A commit message must still open, so the configuration loads and falls back.
test_neovim_starts_when_the_plugin_cannot_be_fetched() {
  local fixture nvim
  fixture=$(installer_fixture)
  nvim=$(command -v nvim) || {
    printf '    skipped: nvim is not installed\n'
    return 0
  }
  mkdir -p "$fixture/home/.config/nvim" "$fixture/empty-bin"
  cp "$REPOSITORY_ROOT/neovim/init.lua" "$REPOSITORY_ROOT/neovim/nvim-pack-lock.json" \
    "$fixture/home/.config/nvim/"

  env -i HOME="$fixture/home" PATH="$fixture/empty-bin" "$nvim" --headless \
    '+lua io.stdout:write(vim.g.colors_name, " ", vim.o.shiftwidth, " ", tostring(vim.o.undofile))' \
    +qa >"$fixture/stdout.log" 2>"$fixture/stderr.log" \
    || scenario_fail "nvim exited with a failure: $(cat "$fixture/stderr.log")"

  assert_contains "$fixture/stdout.log" 'habamax 2 true'
}

scenario_run 'the topic links the configuration and the plugin lock' \
  test_the_topic_links_the_configuration_and_the_plugin_lock
scenario_run 'every shell and Git open Neovim' \
  test_every_shell_and_git_open_neovim
scenario_run 'the plugin lock pins the one plugin' \
  test_the_plugin_lock_pins_the_one_plugin
scenario_run 'Neovim starts when the plugin cannot be fetched' \
  test_neovim_starts_when_the_plugin_cannot_be_fetched

scenario_finish
