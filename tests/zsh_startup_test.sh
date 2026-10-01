#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-zsh-startup-tests
TEST_ROOT=$SCENARIO_ROOT

ZSH_BIN=$(command -v zsh) || {
  scenario_fail 'zsh is required'
  exit 1
}
FIXTURE="$TEST_ROOT/repository"
TEST_HOME="$TEST_ROOT/home"
BREW_PREFIX="$TEST_ROOT/homebrew"
MAIN_ARTIFACTS="$TEST_ROOT/main"
OPTIONAL_ARTIFACTS="$TEST_ROOT/optional"
AGENT_ARTIFACTS="$TEST_ROOT/agent"
LOCALE_HOME="$TEST_ROOT/locale-home"

mkdir -p "$LOCALE_HOME"
ln -s "$REPOSITORY_ROOT/zsh/zshenv.symlink" "$LOCALE_HOME/.zshenv"

# A child process checks that the locale is exported, without loading .zshrc.
scenario_write_file "$TEST_ROOT/locale.sh" <<'EOF'
printf '%s\n' "${LC_MESSAGES-unset}|$LANG|$LC_TIME"
EOF

test_conductor_shells_export_english_messages() {
  local mode
  for mode in -c -ilc; do
    # shellcheck disable=SC2016 # The command is evaluated by the child Zsh process.
    scenario_capture "$TEST_ROOT/locale-conductor" env -i \
      HOME="$LOCALE_HOME" ZDOTDIR="$LOCALE_HOME" PATH=/usr/bin:/bin TERM=dumb \
      LANG=pt_BR.UTF-8 LC_MESSAGES=pt_BR.UTF-8 LC_TIME=pt_BR.UTF-8 \
      __CFBundleIdentifier=com.conductor.app \
      "$ZSH_BIN" -d "$mode" '/bin/sh "$1"' zsh "$TEST_ROOT/locale.sh"
    assert_equal 'C|pt_BR.UTF-8|pt_BR.UTF-8' \
      "$(cat "$TEST_ROOT/locale-conductor/stdout.log")" 'Conductor message locale'
    assert_empty "$TEST_ROOT/locale-conductor/stderr.log"
  done
}

test_other_shells_preserve_message_locale() {
  local bundle messages
  for bundle in '' com.apple.Terminal; do
    for messages in unset pt_BR.UTF-8; do
      local -a startup=(env -i
        HOME="$LOCALE_HOME" ZDOTDIR="$LOCALE_HOME" PATH=/usr/bin:/bin
        LANG=pt_BR.UTF-8 LC_TIME=pt_BR.UTF-8 "__CFBundleIdentifier=$bundle")
      if [ "$messages" != unset ]; then
        startup+=("LC_MESSAGES=$messages")
      fi
      # shellcheck disable=SC2016 # The command is evaluated by the child Zsh process.
      scenario_capture "$TEST_ROOT/locale-other" "${startup[@]}" \
        "$ZSH_BIN" -d -c '/bin/sh "$1"' zsh "$TEST_ROOT/locale.sh"
      assert_equal "$messages|pt_BR.UTF-8|pt_BR.UTF-8" \
        "$(cat "$TEST_ROOT/locale-other/stdout.log")" 'non-Conductor message locale'
      assert_empty "$TEST_ROOT/locale-other/stderr.log"
    done
  done
}

test_conductor_git_reports_missing_upstream_in_english() {
  local git_bin
  git_bin=$(command -v git)
  scenario_write_file "$TEST_ROOT/git-upstream.zsh" <<'EOF'
set -e
"$1" init -q -b locale-test "$HOME/repository"
"$1" -C "$HOME/repository" -c user.name=Fixture -c user.email=fixture@example.invalid \
  -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q --allow-empty -m Fixture
"$1" -C "$HOME/repository" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
EOF
  assert_fails_with_status 128 scenario_capture "$TEST_ROOT/locale-git" env -i \
    HOME="$LOCALE_HOME" ZDOTDIR="$LOCALE_HOME" PATH=/usr/bin:/bin \
    LANG=pt_BR.UTF-8 LC_MESSAGES=pt_BR.UTF-8 \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    __CFBundleIdentifier=com.conductor.app \
    "$ZSH_BIN" -d "$TEST_ROOT/git-upstream.zsh" "$git_bin"
  assert_empty "$TEST_ROOT/locale-git/stdout.log"
  assert_contains "$TEST_ROOT/locale-git/stderr.log" "no upstream configured for branch 'locale-test'"
}

mkdir -p \
  "$FIXTURE/alpha/_private" \
  "$FIXTURE/bravo" \
  "$FIXTURE/functions" \
  "$FIXTURE/git" \
  "$FIXTURE/homebrew" \
  "$FIXTURE/system" \
  "$FIXTURE/zsh" \
  "$FIXTURE/_ignored" \
  "$FIXTURE/_scripts" \
  "$FIXTURE/bin" \
  "$FIXTURE/tests" \
  "$TEST_HOME" \
  "$BREW_PREFIX/bin" \
  "$BREW_PREFIX/etc" \
  "$BREW_PREFIX/share/zsh/site-functions" \
  "$BREW_PREFIX/share/zsh-syntax-highlighting"

cp "$REPOSITORY_ROOT/zsh/zshrc.symlink" "$FIXTURE/zsh/zshrc.symlink"
cp "$REPOSITORY_ROOT/zsh/_startup.zsh" "$FIXTURE/zsh/_startup.zsh"
cp "$REPOSITORY_ROOT/zsh/config.zsh" "$FIXTURE/zsh/config.zsh"
cp "$REPOSITORY_ROOT/zsh/completion.zsh" "$FIXTURE/zsh/completion.zsh"
cp "$REPOSITORY_ROOT/zsh/prompt.zsh" "$FIXTURE/zsh/prompt.zsh"
cp "$REPOSITORY_ROOT/zsh/window.zsh" "$FIXTURE/zsh/window.zsh"
cp "$REPOSITORY_ROOT/system/env.zsh" "$FIXTURE/system/env.zsh"
cp "$REPOSITORY_ROOT/system/grc.zsh" "$FIXTURE/system/grc.zsh"
cp "$REPOSITORY_ROOT/system/aliases.zsh" "$FIXTURE/system/aliases.zsh"
cp "$REPOSITORY_ROOT/git/_branch-state.sh" "$FIXTURE/git/_branch-state.sh"
cp "$REPOSITORY_ROOT/git/completion.zsh" "$FIXTURE/git/completion.zsh"
cp "$REPOSITORY_ROOT/_scripts/topic-catalog" "$FIXTURE/_scripts/topic-catalog"
cp "$REPOSITORY_ROOT/_scripts/adapter-checkout.sh" "$FIXTURE/_scripts/adapter-checkout.sh"
cp "$REPOSITORY_ROOT/homebrew/_availability.sh" "$FIXTURE/homebrew/_availability.sh"

# shellcheck disable=SC2016 # The line is evaluated by the child Zsh process.
printf '%s\n' 'print -r -- prompt >> "$SCENARIO_EVENT_LOG"' >>"$FIXTURE/zsh/prompt.zsh"

scenario_write_executable "$FIXTURE/resolver" <<'EOF'
#!/bin/sh
printf '%s\n' "$STARTUP_FIXTURE_ROOT"
EOF

scenario_write_executable "$BREW_PREFIX/bin/brew" <<'EOF'
#!/bin/sh
printf '%s\n' brew-prefix >> "$SCENARIO_EVENT_LOG"
if [ "$1" = --prefix ]; then
  printf '%s\n' "$FAKE_HOMEBREW_PREFIX"
fi
EOF

scenario_write_executable "$BREW_PREFIX/bin/grc" <<'EOF'
#!/bin/sh
exit 0
EOF

for replacement in eza bat; do
  scenario_write_executable "$BREW_PREFIX/bin/$replacement" <<'EOF'
#!/bin/sh
exit 0
EOF
done

scenario_write_file "$BREW_PREFIX/etc/grc.bashrc" <<'EOF'
print -r -- grc >> "$SCENARIO_EVENT_LOG"
typeset -g FAKE_GRC_LOADED=1
EOF

scenario_write_file "$BREW_PREFIX/share/zsh/site-functions/_git" <<'EOF'
print -r -- git-completion >> "$SCENARIO_EVENT_LOG"
typeset -g FAKE_GIT_COMPLETION_LOADED=1
EOF

scenario_write_file "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" <<'EOF'
print -r -- syntax-highlighting >> "$SCENARIO_EVENT_LOG"
typeset -gA ZSH_HIGHLIGHT_STYLES
typeset -g FAKE_SYNTAX_LOADED=1
EOF

scenario_write_file "$FIXTURE/functions/compinit" <<'EOF'
print -r -- compinit >> "$SCENARIO_EVENT_LOG"
compdef() {
  if [[ $1 == _git && $2 == git ]]; then
    print -r -- git-completion >> "$SCENARIO_EVENT_LOG"
    typeset -g FAKE_GIT_COMPLETION_LOADED=1
  fi
}
EOF

scenario_write_file "$FIXTURE/functions/sample_function" <<'EOF'
print -r -- sample-function
EOF

# WORKSPACE is set here, and PROJECTS is derived from it in .commonrc below,
# because that is the ordering contract: .localrc runs first so an override in
# it reaches the derivation. Startup must not export PROJECTS before either
# file, which would win the `:-` and pin the project root to the default.
scenario_write_file "$TEST_HOME/.localrc" <<'EOF'
print -r -- local-environment >> "$SCENARIO_EVENT_LOG"
export PATH="$PATH:/local/bin"
export WORKSPACE="/overridden/workspace"
EOF

# Mirrors the WORKSPACE and PROJECTS lines of the tracked .commonrc.
scenario_write_file "$FIXTURE/.commonrc" <<'EOF'
print -r -- common-environment >> "$SCENARIO_EVENT_LOG"
export PATH="$PATH:/common/bin"
export WORKSPACE="${WORKSPACE:-$HOME/Workspace}"
export PROJECTS="${PROJECTS:-$WORKSPACE/github.com}"
EOF

scenario_write_file "$FIXTURE/alpha/path.zsh" <<'EOF'
print -r -- path-alpha >> "$SCENARIO_EVENT_LOG"
path+=(/alpha/bin)
EOF

scenario_write_file "$FIXTURE/bravo/path.zsh" <<'EOF'
print -r -- path-bravo >> "$SCENARIO_EVENT_LOG"
path+=(/bravo/bin)
EOF

scenario_write_file "$FIXTURE/alpha/main.zsh" <<'EOF'
print -r -- main-alpha >> "$SCENARIO_EVENT_LOG"
typeset -g STARTUP_ALPHA_MAIN=1
EOF

scenario_write_file "$FIXTURE/bravo/main.zsh" <<'EOF'
print -r -- main-bravo >> "$SCENARIO_EVENT_LOG"
typeset -g STARTUP_BRAVO_MAIN=1
EOF

scenario_write_file "$FIXTURE/alpha/completion.zsh" <<'EOF'
print -r -- completion-alpha >> "$SCENARIO_EVENT_LOG"
typeset -g STARTUP_ALPHA_COMPLETION=1
EOF

scenario_write_file "$FIXTURE/bravo/completion.zsh" <<'EOF'
print -r -- completion-bravo >> "$SCENARIO_EVENT_LOG"
typeset -g STARTUP_BRAVO_COMPLETION=1
EOF

scenario_write_file "$FIXTURE/alpha/_ignored.zsh" <<'EOF'
print -r -- ignored-file >> "$SCENARIO_EVENT_LOG"
EOF

scenario_write_file "$FIXTURE/alpha/_private/nested.zsh" <<'EOF'
print -r -- ignored-directory >> "$SCENARIO_EVENT_LOG"
EOF

scenario_write_file "$FIXTURE/_ignored/config.zsh" <<'EOF'
print -r -- ignored-topic >> "$SCENARIO_EVENT_LOG"
EOF

scenario_write_file "$FIXTURE/bin/reserved.zsh" <<'EOF'
print -r -- ignored-bin >> "$SCENARIO_EVENT_LOG"
EOF

scenario_write_file "$FIXTURE/functions/reserved.zsh" <<'EOF'
print -r -- ignored-functions >> "$SCENARIO_EVENT_LOG"
EOF

scenario_write_file "$FIXTURE/tests/reserved.zsh" <<'EOF'
print -r -- ignored-tests >> "$SCENARIO_EVENT_LOG"
EOF

chmod +x "$FIXTURE/homebrew/_availability.sh" "$FIXTURE/_scripts/topic-catalog"
ln -s "$FIXTURE/resolver" "$TEST_HOME/.dotfiles-root"
ln -s "$FIXTURE/zsh/zshrc.symlink" "$TEST_HOME/.zshrc"

scenario_write_file "$TEST_ROOT/assert-startup.zsh" <<'EOF'
fail() {
  print -u2 -r -- "FAIL: $*"
  exit 1
}

assert_equal() {
  [[ $1 == "$2" ]] || fail "$3 (expected '$1', got '$2')"
}

source "$HOME/.zshrc"

expected_path="$STARTUP_FIXTURE_ROOT/bin:$FAKE_HOMEBREW_PREFIX/bin"
expected_path+=":$FAKE_HOMEBREW_PREFIX/sbin:/usr/local/bin:/usr/local/sbin"
expected_path+=":/base/bin:/usr/bin:/bin:/local/bin:/common/bin"
expected_path+=":/alpha/bin:/bravo/bin:$HOME/.local/bin"
expected_manpath="$FAKE_HOMEBREW_PREFIX/man:/usr/local/man:/usr/local/mysql/man:/usr/local/git/man:/base/man:"
assert_equal "$expected_path" "$PATH" 'PATH order'
assert_equal "$expected_manpath" "$MANPATH" 'MANPATH order'
assert_equal "$FAKE_HOMEBREW_PREFIX" "$HOMEBREW_PREFIX" 'Homebrew prefix'
assert_equal /overridden/workspace/github.com "$PROJECTS" 'project root follows the WORKSPACE override'
assert_equal "$HOME/.zsh_history" "$HISTFILE" 'history file'
assert_equal 100000 "$HISTSIZE" 'history size'
assert_equal 100000 "$SAVEHIST" 'saved history size'

[[ -o APPEND_HISTORY ]] || fail 'APPEND_HISTORY is disabled'
[[ -o INC_APPEND_HISTORY ]] || fail 'INC_APPEND_HISTORY is disabled'
[[ -o SHARE_HISTORY ]] || fail 'SHARE_HISTORY is disabled'
[[ -o EXTENDED_HISTORY ]] || fail 'EXTENDED_HISTORY is disabled'
[[ -o HIST_IGNORE_ALL_DUPS ]] || fail 'HIST_IGNORE_ALL_DUPS is disabled'
[[ -o HIST_REDUCE_BLANKS ]] || fail 'HIST_REDUCE_BLANKS is disabled'
[[ -o COMPLETE_ALIASES ]] && fail 'COMPLETE_ALIASES must stay disabled so aliases expand before completion'
[[ -o COMPLETE_IN_WORD ]] || fail 'COMPLETE_IN_WORD is disabled'
[[ -o AUTO_LIST ]] || fail 'AUTO_LIST is disabled'
[[ -o AUTO_MENU ]] || fail 'AUTO_MENU is disabled'
[[ -o ALWAYS_TO_END ]] || fail 'ALWAYS_TO_END is disabled'

typeset -a matcher_style menu_style
zstyle -a ':completion:*' matcher-list matcher_style
zstyle -a ':completion:*' menu menu_style
assert_equal 'm:{a-z}={A-Z}' "${(j: :)matcher_style}" 'completion matcher style'
assert_equal select "${(j: :)menu_style}" 'completion menu style'
[[ $(bindkey '^[[Z') == *reverse-menu-complete* ]] || fail 'reverse completion binding is missing'

[[ $PROMPT == *'$(battery_status)'* ]] || fail 'custom prompt is not active'
(( ${precmd_functions[(Ie)_dotfiles_prompt_window_title]} )) || \
  fail 'custom prompt hook is not registered'
[[ -z ${functions[precmd]-} ]] || fail 'custom prompt must not override precmd directly'
(( ! $+functions[lprompt] )) || fail 'obsolete Monokai prompt is loaded'
[[ $REPORTTIME == 3 ]] || fail 'command timing threshold changed'
[[ $TIMEFMT == *elapsed:* && $TIMEFMT == *memory:* ]] || fail 'command timing format changed'
[[ $STARTUP_ALPHA_MAIN == 1 && $STARTUP_BRAVO_MAIN == 1 ]] || fail 'main topic files were not sourced'
[[ $STARTUP_ALPHA_COMPLETION == 1 && $STARTUP_BRAVO_COMPLETION == 1 ]] || fail 'completion topic files were not sourced'
[[ $FAKE_GRC_LOADED == 1 ]] || fail 'GRC configuration was not sourced'
[[ $FAKE_GIT_COMPLETION_LOADED == 1 ]] || fail 'Git completion was not registered'
[[ $FAKE_SYNTAX_LOADED == 1 ]] || fail 'syntax highlighting was not sourced'
[[ ${ZSH_HIGHLIGHT_STYLES[path_pathseparator]} == fg=black,bold ]] || fail 'syntax highlighting styles changed'

typeset -a terminal_hooks private_loader_parameters
terminal_hooks=("${(M)precmd_functions:#update_terminal_cwd}")
(( $#terminal_hooks == 1 )) || fail 'Apple Terminal hook is not unique'
private_loader_parameters=(${(k)parameters[(I)_dotfiles_*]})
(( $#private_loader_parameters == 0 )) || fail "private loader state leaked: $private_loader_parameters"

typeset fpath_entry
for fpath_entry in "${fpath[@]}"; do
  [[ $fpath_entry == "$STARTUP_FIXTURE_ROOT/bin" || $fpath_entry == "$STARTUP_FIXTURE_ROOT/tests" ]] && \
    fail "reserved root leaked into fpath: $fpath_entry"
done

typeset first_path=$PATH first_manpath=$MANPATH
typeset -a first_fpath=("$fpath[@]")
print -r -- reload >> "$SCENARIO_EVENT_LOG"
source "$HOME/.zshrc"

assert_equal "$first_path" "$PATH" 'PATH after reload'
assert_equal "$first_manpath" "$MANPATH" 'MANPATH after reload'
assert_equal "${(j.:.)first_fpath}" "${(j.:.)fpath}" 'fpath after reload'
typeset -i user_local_count=0 function_fpath_count=0
typeset entry
for entry in "${path[@]}"; do
  [[ $entry == "$HOME/.local/bin" ]] && (( user_local_count++ ))
done
for entry in "${fpath[@]}"; do
  [[ $entry == "$STARTUP_FIXTURE_ROOT/functions" ]] && (( function_fpath_count++ ))
done
(( user_local_count == 1 )) || \
  fail "user-local PATH entry is duplicated or missing: ${(j.:.)path}"
(( function_fpath_count == 1 )) || \
  fail "function fpath entry is duplicated or missing: ${(j.:.)fpath}"
terminal_hooks=("${(M)precmd_functions:#update_terminal_cwd}")
(( $#terminal_hooks == 1 )) || fail 'Apple Terminal hook duplicated after reload'
typeset -a prompt_hooks
prompt_hooks=("${(M)precmd_functions:#_dotfiles_prompt_window_title}")
(( $#prompt_hooks == 1 )) || fail 'custom prompt hook duplicated after reload'
private_loader_parameters=(${(k)parameters[(I)_dotfiles_*]})
(( $#private_loader_parameters == 0 )) || fail "private loader state leaked after reload: $private_loader_parameters"
EOF

STARTUP_PATH="$BREW_PREFIX/bin:/base/bin:/usr/local/bin:/usr/bin:/bin"

test_startup_order_and_reload() {
  local events="$MAIN_ARTIFACTS/events.log"

  if ! scenario_capture "$MAIN_ARTIFACTS" env -u ZSH -u WORKSPACE -u PROJECTS \
    HOME="$TEST_HOME" \
    PATH="$STARTUP_PATH" \
    MANPATH='/base/man:' \
    TERM_PROGRAM=Apple_Terminal \
    STARTUP_FIXTURE_ROOT="$FIXTURE" \
    DOTFILES_HOMEBREW_ROOT="$TEST_ROOT/platform" \
    FAKE_HOMEBREW_PREFIX="$BREW_PREFIX" \
    "$ZSH_BIN" -d -f "$TEST_ROOT/assert-startup.zsh"; then
    command cat "$MAIN_ARTIFACTS/stderr.log" >&2
    scenario_fail 'isolated Zsh startup assertions failed'
  fi

  assert_before "$events" local-environment common-environment
  assert_before "$events" common-environment brew-prefix
  assert_before "$events" brew-prefix path-alpha
  assert_before "$events" path-alpha path-bravo
  assert_before "$events" path-bravo main-alpha
  assert_before "$events" main-alpha main-bravo
  assert_before "$events" main-bravo grc
  assert_before "$events" grc prompt
  assert_before "$events" prompt compinit
  assert_before "$events" compinit completion-alpha
  assert_before "$events" completion-alpha completion-bravo
  assert_before "$events" completion-bravo git-completion
  assert_before "$events" git-completion syntax-highlighting
  assert_before "$events" syntax-highlighting reload
  assert_count "$events" brew-prefix 2
  assert_count "$events" compinit 2
  assert_count "$events" syntax-highlighting 2
  assert_not_contains "$events" ignored-file
  assert_not_contains "$events" ignored-directory
  assert_not_contains "$events" ignored-topic
  assert_not_contains "$events" ignored-bin
  assert_not_contains "$events" ignored-functions
  assert_not_contains "$events" ignored-tests
}

test_optional_homebrew_integration() {
  local events="$OPTIONAL_ARTIFACTS/events.log"

  # shellcheck disable=SC2016 # The command is evaluated by the child Zsh process.
  if ! scenario_capture "$OPTIONAL_ARTIFACTS" env -u ZSH -u WORKSPACE -u PROJECTS \
    HOME="$TEST_HOME" \
    PATH="$STARTUP_PATH" \
    MANPATH='/base/man:' \
    STARTUP_FIXTURE_ROOT="$FIXTURE" \
    DOTFILES_HOMEBREW_ROOT="$TEST_ROOT/platform" \
    FAKE_HOMEBREW_PREFIX="$TEST_ROOT/missing-homebrew-prefix" \
    EXPECTED_FALLBACK_PREFIX="$TEST_ROOT/platform/usr/local" \
    "$ZSH_BIN" -d -f -c 'source "$HOME/.zshrc"; [[ $HOMEBREW_PREFIX == "$EXPECTED_FALLBACK_PREFIX" && -z ${FAKE_SYNTAX_LOADED-} ]]'; then
    command cat "$OPTIONAL_ARTIFACTS/stderr.log" >&2
    scenario_fail 'startup failed without optional syntax highlighting'
  fi
  assert_not_contains "$events" syntax-highlighting
}

test_agent_shells_keep_standard_file_commands() {
  local marker
  local -a startup=(env -u ZSH -u WORKSPACE -u PROJECTS -u CLAUDECODE -u CODEX_SHELL
    HOME="$TEST_HOME"
    PATH="$STARTUP_PATH"
    MANPATH='/base/man:'
    STARTUP_FIXTURE_ROOT="$FIXTURE"
    DOTFILES_HOMEBREW_ROOT="$TEST_ROOT/platform"
    FAKE_HOMEBREW_PREFIX="$BREW_PREFIX")

  # shellcheck disable=SC2016 # The command is evaluated by the child Zsh process.
  if ! scenario_capture "$AGENT_ARTIFACTS/person" "${startup[@]}" \
    "$ZSH_BIN" -d -f -c 'source "$HOME/.zshrc"; [[ ${aliases[ls]-} == "eza --icons=auto" && ${aliases[cat]-} == bat ]]'; then
    scenario_fail "a person's shell must keep the eza and bat replacements"
  fi
  # Claude Code and Codex replay this startup into their tool shells.
  for marker in CLAUDECODE CODEX_SHELL; do
    # shellcheck disable=SC2016 # The command is evaluated by the child Zsh process.
    if ! scenario_capture "$AGENT_ARTIFACTS/$marker" "${startup[@]}" "$marker=1" \
      "$ZSH_BIN" -d -f -c 'source "$HOME/.zshrc"; (( ! $+aliases[ls] && ! $+aliases[cat] ))'; then
      scenario_fail "$marker shells must keep the standard ls and cat"
    fi
  done
}

test_nested_topic_changes_refresh_cached_startup() {
  local fixture nested cache
  fixture=$(scenario_tmpdir nested-cache)
  nested="$FIXTURE/alpha/nested/deeper"
  cache="$fixture/cache/dotfiles/topic-catalog${FIXTURE//\//%}"
  mkdir -p "$nested" "$fixture/home"
  ln -s "$FIXTURE/resolver" "$fixture/home/.dotfiles-root"

  scenario_write_file "$fixture/start.zsh" <<'EOF'
source "$STARTUP_FIXTURE_ROOT/zsh/zshrc.symlink" || exit 1
print -r -- "nested=${STARTUP_NESTED:-absent}"
EOF

  local -a startup=(env -u ZSH -u WORKSPACE -u PROJECTS
    HOME="$fixture/home"
    XDG_CACHE_HOME="$fixture/cache"
    PATH="$STARTUP_PATH"
    STARTUP_FIXTURE_ROOT="$FIXTURE"
    DOTFILES_HOMEBREW_ROOT="$TEST_ROOT/platform"
    FAKE_HOMEBREW_PREFIX="$BREW_PREFIX"
    "$ZSH_BIN" -d -f "$fixture/start.zsh")

  scenario_capture "$fixture/initial" "${startup[@]}"
  assert_contains "$fixture/initial/stdout.log" 'nested=absent'
  [ -s "$cache" ] || scenario_fail 'startup did not populate the catalog cache'

  # Only the directory changed by each operation may be newer than the cache.
  # Fixed mtimes avoid sleeps and filesystem timestamp-resolution races.
  find "$FIXTURE" -type d -exec touch -t 200001010000 {} +
  touch -t 200001020000 "$cache"
  scenario_write_file "$nested/added.zsh" <<'EOF'
typeset -g STARTUP_NESTED=loaded
EOF
  scenario_capture "$fixture/added" "${startup[@]}"
  assert_contains "$fixture/added/stdout.log" 'nested=loaded'

  find "$FIXTURE" -type d -exec touch -t 200001010000 {} +
  touch -t 200001020000 "$cache"
  mv "$nested/added.zsh" "$nested/disabled.txt"
  scenario_capture "$fixture/renamed" "${startup[@]}"
  assert_contains "$fixture/renamed/stdout.log" 'nested=absent'
  assert_empty "$fixture/renamed/stderr.log"

  find "$FIXTURE" -type d -exec touch -t 200001010000 {} +
  touch -t 200001020000 "$cache"
  mv "$nested/disabled.txt" "$nested/restored.zsh"
  scenario_capture "$fixture/restored" "${startup[@]}"
  assert_contains "$fixture/restored/stdout.log" 'nested=loaded'

  find "$FIXTURE" -type d -exec touch -t 200001010000 {} +
  touch -t 200001020000 "$cache"
  rm "$nested/restored.zsh"
  scenario_capture "$fixture/removed" "${startup[@]}"
  assert_contains "$fixture/removed/stdout.log" 'nested=absent'
  assert_empty "$fixture/removed/stderr.log"
}

scenario_run 'startup follows the documented order and remains idempotent' test_startup_order_and_reload
scenario_run 'Conductor exports English messages in command and login shells' test_conductor_shells_export_english_messages
scenario_run 'other shells preserve their message locale' test_other_shells_preserve_message_locale
scenario_run 'Conductor Git reports a missing upstream in English' test_conductor_git_reports_missing_upstream_in_english
scenario_run 'optional Homebrew integration may be absent' test_optional_homebrew_integration
scenario_run 'coding agent shells keep the standard ls and cat' test_agent_shells_keep_standard_file_commands
scenario_run 'nested topic additions, renames and removals refresh cached startup' \
  test_nested_topic_changes_refresh_cached_startup
scenario_finish
