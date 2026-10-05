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

# Output that reaches a pipe is read by a program, whichever app started the
# shell and however much of startup it runs.
test_tool_shells_export_english_messages() {
  local bundle mode
  for bundle in '' com.conductor.app; do
    for mode in -c -ilc; do
      # shellcheck disable=SC2016 # The command is evaluated by the child Zsh process.
      scenario_capture "$TEST_ROOT/locale-tool" env -i \
        HOME="$LOCALE_HOME" ZDOTDIR="$LOCALE_HOME" PATH=/usr/bin:/bin TERM=dumb \
        LANG=pt_BR.UTF-8 LC_MESSAGES=pt_BR.UTF-8 LC_TIME=pt_BR.UTF-8 \
        "__CFBundleIdentifier=$bundle" \
        "$ZSH_BIN" -d "$mode" '/bin/sh "$1"' zsh "$TEST_ROOT/locale.sh"
      assert_equal 'C|en_US.UTF-8|pt_BR.UTF-8' \
        "$(cat "$TEST_ROOT/locale-tool/stdout.log")" \
        "tool shell locale ($mode, bundle '$bundle')"
      assert_empty "$TEST_ROOT/locale-tool/stderr.log"
    done
  done
}

# A terminal means a person reads the output, in Conductor's integrated
# terminal too. A message override inherited from a tool shell, such as an
# editor that captured its environment without a terminal, does not survive.
test_person_shells_export_portuguese_messages() {
  local bundle messages mode output
  for bundle in '' com.conductor.app; do
    for messages in unset C; do
      for mode in -c -ilc; do
        local -a startup=(env -i
          HOME="$LOCALE_HOME" ZDOTDIR="$LOCALE_HOME" PATH=/usr/bin:/bin TERM=dumb
          LANG=en_US.UTF-8 LC_TIME=en_US.UTF-8 "__CFBundleIdentifier=$bundle")
        if [ "$messages" != unset ]; then
          startup+=("LC_MESSAGES=$messages")
        fi
        # shellcheck disable=SC2016 # The command is evaluated by the child Zsh process.
        output=$(scenario_on_terminal "${startup[@]}" \
          "$ZSH_BIN" -d "$mode" '/bin/sh "$1"' zsh "$TEST_ROOT/locale.sh" | tr -d '\r')
        assert_equal 'unset|pt_BR.UTF-8|en_US.UTF-8' "$output" \
          "person's shell locale ($mode, bundle '$bundle', inherited messages $messages)"
      done
    done
  done
}

# Conductor captures its environment with `$SHELL -ilc env`, which runs the
# shared defaults after ~/.zshenv, so they must not replace either locale.
test_shared_defaults_keep_the_shell_locale() {
  local output
  # shellcheck disable=SC2016 # The command is evaluated by the child Zsh process.
  local probe='source "$1/.commonrc"; printf "%s\n" "${LC_MESSAGES-unset}|$LANG"'
  local -a startup=(env -i
    HOME="$LOCALE_HOME" ZDOTDIR="$LOCALE_HOME" PATH=/usr/bin:/bin TERM=dumb
    __CFBundleIdentifier=com.conductor.app)

  scenario_capture "$TEST_ROOT/locale-shared" "${startup[@]}" LANG=pt_BR.UTF-8 \
    "$ZSH_BIN" -d -ilc "$probe" zsh "$REPOSITORY_ROOT"
  assert_equal 'C|en_US.UTF-8' "$(cat "$TEST_ROOT/locale-shared/stdout.log")" \
    'tool shell locale after the shared defaults'
  assert_empty "$TEST_ROOT/locale-shared/stderr.log"

  output=$(scenario_on_terminal "${startup[@]}" LANG=en_US.UTF-8 LC_MESSAGES=C \
    "$ZSH_BIN" -d -ilc "$probe" zsh "$REPOSITORY_ROOT" | tr -d '\r')
  assert_equal 'unset|pt_BR.UTF-8' "$output" \
    "person's shell locale after the shared defaults"
}

test_tool_shell_git_reports_missing_upstream_in_english() {
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
    "$ZSH_BIN" -d "$TEST_ROOT/git-upstream.zsh" "$git_bin"
  assert_empty "$TEST_ROOT/locale-git/stdout.log"
  assert_contains "$TEST_ROOT/locale-git/stderr.log" "no upstream configured for branch 'locale-test'"
}

test_conductor_git_child_uses_captured_locale() {
  local git_bin captured_lang repository
  git_bin=$(command -v git)
  repository="$TEST_ROOT/conductor-git-child"
  env -i HOME="$LOCALE_HOME" PATH=/usr/bin:/bin \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    "$git_bin" init -q -b locale-test "$repository"
  env -i HOME="$LOCALE_HOME" PATH=/usr/bin:/bin \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    "$git_bin" -C "$repository" -c user.name=Fixture -c user.email=fixture@example.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q --allow-empty -m Fixture

  # Conductor forwards LANG to clean zsh -f children, but not LC_MESSAGES.
  # shellcheck disable=SC2016 # The child Zsh evaluates its captured locale.
  captured_lang=$(env -i \
    HOME="$LOCALE_HOME" ZDOTDIR="$LOCALE_HOME" PATH=/usr/bin:/bin \
    LANG=pt_BR.UTF-8 __CFBundleIdentifier=com.conductor.app \
    "$ZSH_BIN" -d -c 'printf "%s" "$LANG"')
  # shellcheck disable=SC2016 # Arguments are expanded by the child Zsh.
  assert_fails_with_status 128 scenario_capture "$TEST_ROOT/locale-git-child" env -i \
    HOME="$LOCALE_HOME" ZDOTDIR="$LOCALE_HOME" PATH=/usr/bin:/bin \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    "$ZSH_BIN" -f -c \
    'export LANG="$1"; "$2" -C "$3" rev-parse --abbrev-ref --symbolic-full-name "@{upstream}"' \
    zsh "$captured_lang" "$git_bin" "$repository"
  assert_empty "$TEST_ROOT/locale-git-child/stdout.log"
  assert_contains "$TEST_ROOT/locale-git-child/stderr.log" "no upstream configured for branch 'locale-test'"
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
cp "$REPOSITORY_ROOT/homebrew/_availability.sh" "$FIXTURE/homebrew/_availability.sh"

# shellcheck disable=SC2016 # The line is evaluated by the child Zsh process.
printf '%s\n' 'print -r -- prompt >> "$SCENARIO_EVENT_LOG"' >>"$FIXTURE/zsh/prompt.zsh"

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
ln -s "$FIXTURE/zsh/zshrc.symlink" "$TEST_HOME/.zshrc"
ln -s "$REPOSITORY_ROOT/zsh/zshenv.symlink" "$TEST_HOME/.zshenv"

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
# .commonrc keeps the caller's XDG cache, data and state homes, so a startup
# file writing below them reached the real home: the catalog cache once filled
# ~/.cache/dotfiles with test entries. Unset, they fall back below each
# scenario's HOME.
STARTUP_ENV=(env -u ZSH -u WORKSPACE -u PROJECTS
  -u XDG_CACHE_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME)

test_startup_order_and_reload() {
  local events="$MAIN_ARTIFACTS/events.log"

  if ! scenario_capture "$MAIN_ARTIFACTS" "${STARTUP_ENV[@]}" \
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
  if ! scenario_capture "$OPTIONAL_ARTIFACTS" "${STARTUP_ENV[@]}" \
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

test_only_a_persons_shell_replaces_file_commands() {
  local mode
  # shellcheck disable=SC2016 # The commands are evaluated by the child Zsh process.
  local replaced='source "$HOME/.zshrc"; [[ ${aliases[ls]-} == "eza --icons=auto" && ${aliases[cat]-} == bat ]]'
  # shellcheck disable=SC2016 # The commands are evaluated by the child Zsh process.
  local standard='source "$HOME/.zshrc"; (( ! $+aliases[ls] && ! $+aliases[cat] ))'
  local -a startup=("${STARTUP_ENV[@]}"
    HOME="$TEST_HOME"
    ZDOTDIR="$TEST_HOME"
    PATH="$STARTUP_PATH"
    MANPATH='/base/man:'
    STARTUP_FIXTURE_ROOT="$FIXTURE"
    DOTFILES_HOMEBREW_ROOT="$TEST_ROOT/platform"
    FAKE_HOMEBREW_PREFIX="$BREW_PREFIX")

  mkdir -p "$AGENT_ARTIFACTS"
  if ! scenario_on_terminal "${startup[@]}" SCENARIO_EVENT_LOG=/dev/null \
    "$ZSH_BIN" -d -c "$replaced" >"$AGENT_ARTIFACTS/person.log" 2>&1; then
    command cat "$AGENT_ARTIFACTS/person.log" >&2
    scenario_fail "a person's shell must get the eza and bat replacements"
  fi
  # A shell that skipped ~/.zshenv has no classification and is a person's.
  if ! scenario_capture "$AGENT_ARTIFACTS/unclassified" "${startup[@]}" \
    "$ZSH_BIN" -d -f -c "$replaced"; then
    scenario_fail "a shell that skipped ~/.zshenv must get the replacements"
  fi
  # Claude Code and Codex replay this startup through a login shell without a
  # terminal and keep the aliases for their command shells.
  for mode in -c -lc; do
    if ! scenario_capture "$AGENT_ARTIFACTS/tool$mode" "${startup[@]}" \
      "$ZSH_BIN" -d "$mode" "$standard"; then
      command cat "$AGENT_ARTIFACTS/tool$mode/stderr.log" >&2
      scenario_fail "a tool shell ($mode) must keep the standard ls and cat"
    fi
  done
}

# The next shell must see the checkout as it is now. Startup classifies on
# every pass, so this holds by construction; the test stays because a memo
# brought back would break it, as the old one did for nested directories.
test_nested_topic_changes_reach_the_next_shell() {
  local fixture nested
  fixture=$(scenario_tmpdir nested-topic)
  nested="$FIXTURE/alpha/nested/deeper"
  mkdir -p "$nested" "$fixture/home"

  scenario_write_file "$fixture/start.zsh" <<'EOF'
source "$STARTUP_FIXTURE_ROOT/zsh/zshrc.symlink" || exit 1
print -r -- "nested=${STARTUP_NESTED:-absent}"
EOF

  local -a startup=("${STARTUP_ENV[@]}"
    HOME="$fixture/home"
    PATH="$STARTUP_PATH"
    STARTUP_FIXTURE_ROOT="$FIXTURE"
    DOTFILES_HOMEBREW_ROOT="$TEST_ROOT/platform"
    FAKE_HOMEBREW_PREFIX="$BREW_PREFIX"
    "$ZSH_BIN" -d -f "$fixture/start.zsh")

  scenario_capture "$fixture/initial" "${startup[@]}"
  assert_contains "$fixture/initial/stdout.log" 'nested=absent'

  scenario_write_file "$nested/added.zsh" <<'EOF'
typeset -g STARTUP_NESTED=loaded
EOF
  scenario_capture "$fixture/added" "${startup[@]}"
  assert_contains "$fixture/added/stdout.log" 'nested=loaded'

  rm "$nested/added.zsh"
  scenario_capture "$fixture/removed" "${startup[@]}"
  assert_contains "$fixture/removed/stdout.log" 'nested=absent'
  assert_empty "$fixture/removed/stderr.log"
}

# ~/.zshrc reaches the checkout through a symbolic link. Startup acts on the
# checkout containing the startup file, not on one an inherited DOTFILES_ROOT
# names, and a ~/.dotfiles-root left by an older setup plays no part, even
# when it names a worktree that has since been removed.
test_startup_acts_on_the_checkout_containing_it() {
  local fixture
  fixture=$(scenario_tmpdir containing-checkout)
  mkdir -p "$fixture/home" "$fixture/other-checkout"
  ln -s "$FIXTURE/zsh/zshrc.symlink" "$fixture/home/.zshrc"
  ln -s "$fixture/removed-worktree/dotfiles-root.symlink" "$fixture/home/.dotfiles-root"

  scenario_write_file "$fixture/start.zsh" <<'EOF'
source "$HOME/.zshrc" || exit 1
print -r -- "$DOTFILES_ROOT" >| "$HOME/checkout"
EOF

  scenario_capture "$fixture" "${STARTUP_ENV[@]}" \
    HOME="$fixture/home" \
    PATH="$STARTUP_PATH" \
    DOTFILES_ROOT="$fixture/other-checkout" \
    STARTUP_FIXTURE_ROOT="$FIXTURE" \
    DOTFILES_HOMEBREW_ROOT="$TEST_ROOT/platform" \
    FAKE_HOMEBREW_PREFIX="$BREW_PREFIX" \
    "$ZSH_BIN" -d -f "$fixture/start.zsh"
  assert_equal "$FIXTURE" "$(command cat "$fixture/home/checkout")" 'checkout containing the startup file'
  assert_empty "$fixture/stderr.log"
}

scenario_run 'startup follows the documented order and remains idempotent' test_startup_order_and_reload
scenario_run 'tool shells export English messages whichever app started them' test_tool_shells_export_english_messages
scenario_run "a person's shell exports Portuguese messages on a terminal" test_person_shells_export_portuguese_messages
scenario_run 'shared defaults keep the locale of each kind of shell' test_shared_defaults_keep_the_shell_locale
scenario_run 'Git in a tool shell reports a missing upstream in English' test_tool_shell_git_reports_missing_upstream_in_english
scenario_run 'Conductor Git children use the captured locale without startup files' test_conductor_git_child_uses_captured_locale
scenario_run 'optional Homebrew integration may be absent' test_optional_homebrew_integration
scenario_run "only a person's shell replaces ls and cat" test_only_a_persons_shell_replaces_file_commands
scenario_run 'nested topic additions and removals reach the next shell' \
  test_nested_topic_changes_reach_the_next_shell
scenario_run 'startup acts on the checkout containing it' \
  test_startup_acts_on_the_checkout_containing_it
scenario_finish
