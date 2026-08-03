#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-zsh-startup-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file=$1 expected=$2
  grep -Fq "$expected" "$file" || fail "expected $file to contain: $expected"
}

assert_not_contains() {
  local file=$1 unexpected=$2
  if grep -Fq "$unexpected" "$file"; then
    fail "expected $file not to contain: $unexpected"
  fi
}

assert_count() {
  local file=$1 pattern=$2 expected=$3 actual
  actual=$(grep -Fc "$pattern" "$file" || true)
  [[ $actual -eq $expected ]] || \
    fail "expected $expected occurrences of '$pattern' in $file, got $actual"
}

assert_before() {
  local file=$1 first=$2 second=$3 first_line second_line
  first_line=$(grep -nF "$first" "$file" | head -n 1 | cut -d: -f1)
  second_line=$(grep -nF "$second" "$file" | head -n 1 | cut -d: -f1)
  [[ -n $first_line ]] || fail "missing '$first' in $file"
  [[ -n $second_line ]] || fail "missing '$second' in $file"
  [[ $first_line -lt $second_line ]] || \
    fail "expected '$first' before '$second' in $file"
}

ZSH_BIN=$(command -v zsh) || fail 'zsh is required'
FIXTURE="$TEST_ROOT/repository"
TEST_HOME="$TEST_ROOT/home"
BREW_PREFIX="$TEST_ROOT/homebrew"
EVENTS="$TEST_ROOT/events.log"
OPTIONAL_EVENTS="$TEST_ROOT/optional-events.log"

mkdir -p \
  "$FIXTURE/alpha/_private" \
  "$FIXTURE/bravo" \
  "$FIXTURE/functions" \
  "$FIXTURE/git" \
  "$FIXTURE/system" \
  "$FIXTURE/zsh" \
  "$FIXTURE/_ignored" \
  "$FIXTURE/bin" \
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
cp "$REPOSITORY_ROOT/git/_branch-state.sh" "$FIXTURE/git/_branch-state.sh"
cp "$REPOSITORY_ROOT/git/completion.zsh" "$FIXTURE/git/completion.zsh"

# shellcheck disable=SC2016 # The line is evaluated by the child Zsh process.
printf '%s\n' 'print -r -- prompt >> "$STARTUP_TEST_LOG"' >> "$FIXTURE/zsh/prompt.zsh"

cat > "$FIXTURE/resolver" <<'EOF'
#!/bin/sh
printf '%s\n' "$STARTUP_FIXTURE_ROOT"
EOF

cat > "$BREW_PREFIX/bin/brew" <<'EOF'
#!/bin/sh
printf '%s\n' brew-prefix >> "$STARTUP_TEST_LOG"
if [ "$1" = --prefix ]; then
  printf '%s\n' "$FAKE_HOMEBREW_PREFIX"
fi
EOF

cat > "$BREW_PREFIX/bin/grc" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$BREW_PREFIX/etc/grc.bashrc" <<'EOF'
print -r -- grc >> "$STARTUP_TEST_LOG"
typeset -g FAKE_GRC_LOADED=1
EOF

cat > "$BREW_PREFIX/share/zsh/site-functions/_git" <<'EOF'
print -r -- git-completion >> "$STARTUP_TEST_LOG"
typeset -g FAKE_GIT_COMPLETION_LOADED=1
EOF

cat > "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" <<'EOF'
print -r -- syntax-highlighting >> "$STARTUP_TEST_LOG"
typeset -gA ZSH_HIGHLIGHT_STYLES
typeset -g FAKE_SYNTAX_LOADED=1
EOF

cat > "$FIXTURE/functions/compinit" <<'EOF'
print -r -- compinit >> "$STARTUP_TEST_LOG"
compdef() {
  if [[ $1 == _git && $2 == git ]]; then
    print -r -- git-completion >> "$STARTUP_TEST_LOG"
    typeset -g FAKE_GIT_COMPLETION_LOADED=1
  fi
}
EOF

cat > "$FIXTURE/functions/sample_function" <<'EOF'
print -r -- sample-function
EOF

cat > "$TEST_HOME/.localrc" <<'EOF'
print -r -- local-environment >> "$STARTUP_TEST_LOG"
export PATH="$PATH:/local/bin"
EOF

cat > "$FIXTURE/.commonrc" <<'EOF'
print -r -- common-environment >> "$STARTUP_TEST_LOG"
export PATH="$PATH:/common/bin"
EOF

cat > "$FIXTURE/alpha/path.zsh" <<'EOF'
print -r -- path-alpha >> "$STARTUP_TEST_LOG"
path+=(/alpha/bin)
EOF

cat > "$FIXTURE/bravo/path.zsh" <<'EOF'
print -r -- path-bravo >> "$STARTUP_TEST_LOG"
path+=(/bravo/bin)
EOF

cat > "$FIXTURE/alpha/main.zsh" <<'EOF'
print -r -- main-alpha >> "$STARTUP_TEST_LOG"
typeset -g STARTUP_ALPHA_MAIN=1
EOF

cat > "$FIXTURE/bravo/main.zsh" <<'EOF'
print -r -- main-bravo >> "$STARTUP_TEST_LOG"
typeset -g STARTUP_BRAVO_MAIN=1
EOF

cat > "$FIXTURE/alpha/completion.zsh" <<'EOF'
print -r -- completion-alpha >> "$STARTUP_TEST_LOG"
typeset -g STARTUP_ALPHA_COMPLETION=1
EOF

cat > "$FIXTURE/bravo/completion.zsh" <<'EOF'
print -r -- completion-bravo >> "$STARTUP_TEST_LOG"
typeset -g STARTUP_BRAVO_COMPLETION=1
EOF

cat > "$FIXTURE/alpha/_ignored.zsh" <<'EOF'
print -r -- ignored-file >> "$STARTUP_TEST_LOG"
EOF

cat > "$FIXTURE/alpha/_private/nested.zsh" <<'EOF'
print -r -- ignored-directory >> "$STARTUP_TEST_LOG"
EOF

cat > "$FIXTURE/_ignored/config.zsh" <<'EOF'
print -r -- ignored-topic >> "$STARTUP_TEST_LOG"
EOF

chmod +x "$FIXTURE/resolver" "$BREW_PREFIX/bin/brew" "$BREW_PREFIX/bin/grc"
ln -s "$FIXTURE/resolver" "$TEST_HOME/.dotfiles-root"
ln -s "$FIXTURE/zsh/zshrc.symlink" "$TEST_HOME/.zshrc"

cat > "$TEST_ROOT/assert-startup.zsh" <<'EOF'
fail() {
  print -u2 -r -- "FAIL: $*"
  exit 1
}

assert_equal() {
  [[ $1 == "$2" ]] || fail "$3 (expected '$1', got '$2')"
}

source "$HOME/.zshrc"

expected_path="$FAKE_HOMEBREW_PREFIX/bin:$FAKE_HOMEBREW_PREFIX/sbin"
expected_path+=":/usr/local/bin:/usr/local/sbin:$STARTUP_FIXTURE_ROOT/bin"
expected_path+=":/base/bin:/usr/bin:/bin:/local/bin:/common/bin"
expected_path+=":/alpha/bin:/bravo/bin:$HOME/.local/bin"
expected_manpath="$FAKE_HOMEBREW_PREFIX/man:/usr/local/man:/usr/local/mysql/man:/usr/local/git/man:/base/man:"
assert_equal "$expected_path" "$PATH" 'PATH order'
assert_equal "$expected_manpath" "$MANPATH" 'MANPATH order'
assert_equal "$FAKE_HOMEBREW_PREFIX" "$HOMEBREW_PREFIX" 'Homebrew prefix'
assert_equal "$HOME/Code" "$PROJECTS" 'project root'
assert_equal "$HOME/.zsh_history" "$HISTFILE" 'history file'
assert_equal 10000 "$HISTSIZE" 'history size'
assert_equal 10000 "$SAVEHIST" 'saved history size'

[[ -o APPEND_HISTORY ]] || fail 'APPEND_HISTORY is disabled'
[[ -o INC_APPEND_HISTORY ]] || fail 'INC_APPEND_HISTORY is disabled'
[[ -o SHARE_HISTORY ]] || fail 'SHARE_HISTORY is disabled'
[[ -o EXTENDED_HISTORY ]] || fail 'EXTENDED_HISTORY is disabled'
[[ -o HIST_IGNORE_ALL_DUPS ]] || fail 'HIST_IGNORE_ALL_DUPS is disabled'
[[ -o HIST_REDUCE_BLANKS ]] || fail 'HIST_REDUCE_BLANKS is disabled'
[[ -o COMPLETE_ALIASES ]] || fail 'COMPLETE_ALIASES is disabled'
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
[[ ${functions[precmd]} == *set_prompt* ]] || fail 'custom prompt does not own precmd'
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

typeset first_path=$PATH first_manpath=$MANPATH
typeset -a first_fpath=("$fpath[@]")
print -r -- reload >> "$STARTUP_TEST_LOG"
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
private_loader_parameters=(${(k)parameters[(I)_dotfiles_*]})
(( $#private_loader_parameters == 0 )) || fail "private loader state leaked after reload: $private_loader_parameters"
EOF

STARTUP_PATH="$BREW_PREFIX/bin:/base/bin:/usr/local/bin:/usr/bin:/bin"
if ! env -u ZSH \
  HOME="$TEST_HOME" \
  PATH="$STARTUP_PATH" \
  MANPATH='/base/man:' \
  TERM_PROGRAM=Apple_Terminal \
  STARTUP_FIXTURE_ROOT="$FIXTURE" \
  STARTUP_TEST_LOG="$EVENTS" \
  FAKE_HOMEBREW_PREFIX="$BREW_PREFIX" \
  "$ZSH_BIN" -d -f "$TEST_ROOT/assert-startup.zsh"
then
  fail 'isolated Zsh startup assertions failed'
fi

assert_before "$EVENTS" local-environment common-environment
assert_before "$EVENTS" common-environment brew-prefix
assert_before "$EVENTS" brew-prefix path-alpha
assert_before "$EVENTS" path-alpha path-bravo
assert_before "$EVENTS" path-bravo main-alpha
assert_before "$EVENTS" main-alpha main-bravo
assert_before "$EVENTS" main-bravo grc
assert_before "$EVENTS" grc prompt
assert_before "$EVENTS" prompt compinit
assert_before "$EVENTS" compinit completion-alpha
assert_before "$EVENTS" completion-alpha completion-bravo
assert_before "$EVENTS" completion-bravo git-completion
assert_before "$EVENTS" git-completion syntax-highlighting
assert_before "$EVENTS" syntax-highlighting reload
assert_count "$EVENTS" brew-prefix 2
assert_count "$EVENTS" compinit 2
assert_count "$EVENTS" syntax-highlighting 2
assert_not_contains "$EVENTS" ignored-file
assert_not_contains "$EVENTS" ignored-directory
assert_not_contains "$EVENTS" ignored-topic

# A missing Homebrew syntax-highlighting script must not prevent startup.
# shellcheck disable=SC2016 # The command is evaluated by the child Zsh process.
if ! env -u ZSH \
  HOME="$TEST_HOME" \
  PATH="$STARTUP_PATH" \
  MANPATH='/base/man:' \
  STARTUP_FIXTURE_ROOT="$FIXTURE" \
  STARTUP_TEST_LOG="$OPTIONAL_EVENTS" \
  FAKE_HOMEBREW_PREFIX="$TEST_ROOT/missing-homebrew-prefix" \
  "$ZSH_BIN" -d -f -c 'source "$HOME/.zshrc"; [[ -z ${FAKE_SYNTAX_LOADED-} ]]'
then
  fail 'startup failed without optional syntax highlighting'
fi
assert_not_contains "$OPTIONAL_EVENTS" syntax-highlighting

printf 'PASS: Zsh startup orchestration\n'
