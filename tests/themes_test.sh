#!/usr/bin/env bash
#
# One theme for every tool. The system appearance selects nothing: a tool that
# followed it would be the only one to change.

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
# shellcheck source=tests/_support/jsonc.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/jsonc.sh"
scenario_init dotfiles-themes-tests

# Usage: assert_links_to <link> <repository-relative source>
assert_links_to() {
  [ -L "$1" ] || {
    scenario_fail "$1 is not a symbolic link"
    return 1
  }
  assert_equal "$REPOSITORY_ROOT/$2" "$(readlink "$1")" "source of $1"
}

test_each_theme_topic_links_its_files() {
  local fixture topic
  fixture=$(installer_fixture)
  for topic in atuin btop eza lazygit; do
    fixture_run "$fixture" -- "$REPOSITORY_ROOT/$topic/install.sh"
  done

  assert_links_to "$fixture/home/.atuin/themes/catppuccin-macchiato-blue.toml" \
    atuin/catppuccin-macchiato-blue.toml
  assert_links_to "$fixture/home/.config/btop/btop.conf" btop/btop.conf
  assert_links_to "$fixture/home/.config/btop/themes/catppuccin_macchiato.theme" \
    btop/catppuccin_macchiato.theme
  assert_links_to "$fixture/home/.config/eza/theme.yml" eza/theme.yml
  assert_links_to "$fixture/home/.config/lazygit/config.yml" lazygit/config.yml
}

# A theme file is only half of it: each tool also has to be told to use it.
test_each_tool_selects_the_linked_theme() {
  assert_contains "$REPOSITORY_ROOT/btop/btop.conf" 'color_theme = "catppuccin_macchiato"'
  assert_contains "$REPOSITORY_ROOT/atuin/env.zsh" \
    'export ATUIN_THEME__NAME=catppuccin-macchiato-blue'
  # shellcheck disable=SC2016 # The literal line eza/env.zsh must hold.
  assert_contains "$REPOSITORY_ROOT/eza/env.zsh" 'export EZA_CONFIG_DIR="$HOME/.config/eza"'
  assert_contains "$REPOSITORY_ROOT/atuin/catppuccin-macchiato-blue.toml" \
    'name = "catppuccin-macchiato-blue"'
}

test_no_tool_follows_the_system_appearance() {
  assert_contains "$REPOSITORY_ROOT/ghostty/config" 'theme = Catppuccin Macchiato'
  assert_not_contains "$REPOSITORY_ROOT/ghostty/config" 'light:'
  jsonc_to_json "$REPOSITORY_ROOT/zed/settings.json" \
    | jq -e '.theme == "Catppuccin Macchiato" and .icon_theme == "Catppuccin Macchiato"' \
      >/dev/null \
    || scenario_fail 'zed/settings.json must fix the theme and the icon theme'
  jq -e '.theme | .dark == "catppuccin-macchiato" and .light == .dark' \
    "$REPOSITORY_ROOT/herdr/settings.json" >/dev/null \
    || scenario_fail 'herdr/settings.json must name one theme for both appearances'
  assert_equal 'Catppuccin Macchiato' \
    "$(git config --file "$REPOSITORY_ROOT/git/gitconfig.symlink" delta.syntax-theme)" \
    'delta syntax theme'
  assert_contains "$REPOSITORY_ROOT/system/env.zsh" 'export BAT_THEME="Catppuccin Macchiato"'
  assert_contains "$REPOSITORY_ROOT/zsh/config.zsh" '--color=bg+:#363A4F,bg:#24273A'
}

# tmux keeps sessions alive; arranging panes is Ghostty's job.
test_tmux_binds_no_pane_navigation() {
  assert_not_contains "$REPOSITORY_ROOT/tmux/tmux.conf.symlink" 'select-pane'
  assert_not_contains "$REPOSITORY_ROOT/tmux/tmux.conf.symlink" 'resize-pane'
}

scenario_run 'each theme topic links its files' \
  test_each_theme_topic_links_its_files
scenario_run 'each tool selects the linked theme' \
  test_each_tool_selects_the_linked_theme
scenario_run 'no tool follows the system appearance' \
  test_no_tool_follows_the_system_appearance
scenario_run 'tmux binds no pane navigation' \
  test_tmux_binds_no_pane_navigation

scenario_finish
