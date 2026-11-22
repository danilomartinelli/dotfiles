#!/usr/bin/env bash
#
# The prompt: what it shows about the repository and the context a command
# would act on, and that drawing it waits for neither.

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-prompt-tests

# Create a fixture with an empty home and a repository on branch `main`.
new_fixture() {
  local fixture
  fixture=$(scenario_tmpdir fixture)
  mkdir -p "$fixture/home" "$fixture/elsewhere"
  env -i HOME="$fixture/home" PATH=/usr/bin:/bin \
    git init -q -b main "$fixture/repository"
  env -i HOME="$fixture/home" PATH=/usr/bin:/bin \
    git -C "$fixture/repository" -c user.name=Fixture -c user.email=fixture@example.invalid \
    commit -q --allow-empty -m Fixture
  printf '%s\n' "$fixture"
}

# Run Zsh code with the prompt loaded, in the fixture repository and without a
# terminal. Usage: with_prompt <fixture> [KEY=value ...] -- <zsh code>
with_prompt() {
  local fixture=$1
  shift
  local -a overrides=()
  while [ "$1" != -- ]; do
    overrides+=("$1")
    shift
  done
  shift

  (
    cd "$fixture/repository" || exit 1
    # shellcheck disable=SC2016 # The child Zsh expands this.
    env -i HOME="$fixture/home" PATH=/usr/bin:/bin DOTFILES_ROOT="$REPOSITORY_ROOT" \
      ${overrides[@]+"${overrides[@]}"} zsh -d -f -c '
        autoload -U colors && colors
        setopt PROMPT_SUBST
        source "$DOTFILES_ROOT/zsh/prompt.zsh"
        '"$1"
  )
}

write_kubeconfig() {
  scenario_write_file "$1" <<EOF_KUBECONFIG
apiVersion: v1
clusters: []
current-context: $2
kind: Config
EOF_KUBECONFIG
}

test_drawing_the_prompt_starts_no_process() {
  local fixture prompt
  fixture=$(new_fixture)
  # shellcheck disable=SC2016 # The child Zsh expands this.
  prompt=$(with_prompt "$fixture" -- 'print -r -- "$PROMPT"')

  # shellcheck disable=SC2016 # These are the literal characters looked for.
  case $prompt in
    *'$('* | *'`'*) scenario_fail "the prompt runs a command substitution: $prompt" ;;
  esac
}

test_the_git_segment_names_the_branch() {
  local fixture
  fixture=$(new_fixture)

  # shellcheck disable=SC2016 # The child Zsh expands this.
  with_prompt "$fixture" -- '_dotfiles_prompt_start_render; print -r -- "$_prompt_git"' \
    >"$fixture/stdout.log"
  assert_contains "$fixture/stdout.log" 'on '
  assert_contains "$fixture/stdout.log" 'main'
}

test_another_directory_drops_the_previous_repository() {
  local fixture
  fixture=$(new_fixture)

  # shellcheck disable=SC2016 # The child Zsh expands this.
  assert_equal '' "$(with_prompt "$fixture" ELSEWHERE="$fixture/elsewhere" -- '
    _dotfiles_prompt_start_render
    cd "$ELSEWHERE"
    _dotfiles_prompt_start_render
    print -r -- "$_prompt_git"')" 'git segment outside a repository'
}

test_the_kubernetes_context_is_shown() {
  local fixture
  fixture=$(new_fixture)
  write_kubeconfig "$fixture/home/.kube/config" '"staging-east"'

  # shellcheck disable=SC2016 # The child Zsh expands this.
  assert_equal '%F{8}k8s:staging-east%f%b' \
    "$(with_prompt "$fixture" -- '_dotfiles_prompt_show_context; print -r -- "$RPROMPT"')" \
    'context from the default kubeconfig'
}

test_the_first_kubeconfig_naming_a_context_wins() {
  local fixture
  fixture=$(new_fixture)
  write_kubeconfig "$fixture/empty" '""'
  write_kubeconfig "$fixture/first" first
  write_kubeconfig "$fixture/second" second

  # shellcheck disable=SC2016 # The child Zsh expands this.
  assert_equal '%F{8}k8s:first%f%b' \
    "$(with_prompt "$fixture" \
      KUBECONFIG="$fixture/missing:$fixture/empty:$fixture/first:$fixture/second" \
      -- '_dotfiles_prompt_show_context; print -r -- "$RPROMPT"')" \
    'context from a kubeconfig list'
}

test_a_changed_kubeconfig_changes_the_context() {
  local fixture
  fixture=$(new_fixture)
  write_kubeconfig "$fixture/home/.kube/config" before

  # shellcheck disable=SC2016 # The child Zsh expands this.
  assert_equal '%F{8}k8s:after%f%b' "$(with_prompt "$fixture" -- '
    _dotfiles_prompt_show_context
    print -r -- "current-context: after" >$HOME/.kube/config
    touch -t 203001010000 $HOME/.kube/config
    _dotfiles_prompt_show_context
    print -r -- "$RPROMPT"')" 'context after the kubeconfig changed'
}

test_a_production_context_is_red() {
  local fixture
  fixture=$(new_fixture)
  write_kubeconfig "$fixture/home/.kube/config" acme-PROD-1

  # shellcheck disable=SC2016 # The child Zsh expands this.
  assert_equal '%B%F{red}k8s:acme-PROD-1%f%b %B%F{red}aws:production%f%b' \
    "$(with_prompt "$fixture" AWS_PROFILE=production \
      -- '_dotfiles_prompt_show_context; print -r -- "$RPROMPT"')" \
    'production contexts'
}

test_the_aws_profile_is_shown_only_when_set() {
  local fixture
  fixture=$(new_fixture)

  # shellcheck disable=SC2016 # The child Zsh expands this.
  assert_equal '' \
    "$(with_prompt "$fixture" -- '_dotfiles_prompt_show_context; print -r -- "$RPROMPT"')" \
    'no context at all'
  # shellcheck disable=SC2016 # The child Zsh expands this.
  assert_equal '%F{8}aws:dev%f%b' \
    "$(with_prompt "$fixture" AWS_VAULT=dev \
      -- '_dotfiles_prompt_show_context; print -r -- "$RPROMPT"')" \
    'profile from an aws-vault session'
}

# On a terminal the first prompt is drawn before the repository is examined,
# and the answer is delivered to the line editor afterwards. The shell leaves
# when it arrives; TMOUT ends a shell it never reached.
test_a_terminal_gets_the_git_segment_after_the_prompt() {
  local fixture
  fixture=$(new_fixture)
  scenario_write_file "$fixture/zdotdir/.zshrc" <<'EOF_ZSHRC'
autoload -U colors && colors
setopt PROMPT_SUBST
title() { : }
source "$DOTFILES_ROOT/zsh/prompt.zsh"
functions[deliver_render]=$functions[_dotfiles_prompt_finish_render]
_dotfiles_prompt_finish_render() {
  print -r -- "drawn with: [$_prompt_git]" >>$RESULT
  deliver_render "$@"
  print -r -- "delivered: $_prompt_git" >>$RESULT
  exit
}
TMOUT=20
cd $REPOSITORY
EOF_ZSHRC

  scenario_on_terminal env -i HOME="$fixture/home" PATH=/usr/bin:/bin TERM=xterm \
    ZDOTDIR="$fixture/zdotdir" DOTFILES_ROOT="$REPOSITORY_ROOT" \
    REPOSITORY="$fixture/repository" RESULT="$fixture/result.log" \
    zsh -d -i >/dev/null || true

  assert_contains "$fixture/result.log" 'drawn with: []'
  assert_contains "$fixture/result.log" 'delivered: on '
  assert_contains "$fixture/result.log" 'main'
}

scenario_run 'drawing the prompt starts no process' \
  test_drawing_the_prompt_starts_no_process
scenario_run 'the git segment names the branch' \
  test_the_git_segment_names_the_branch
scenario_run 'another directory drops the previous repository' \
  test_another_directory_drops_the_previous_repository
scenario_run 'the Kubernetes context is shown' \
  test_the_kubernetes_context_is_shown
scenario_run 'the first kubeconfig naming a context wins' \
  test_the_first_kubeconfig_naming_a_context_wins
scenario_run 'a changed kubeconfig changes the context' \
  test_a_changed_kubeconfig_changes_the_context
scenario_run 'a production context is red' \
  test_a_production_context_is_red
scenario_run 'the AWS profile is shown only when set' \
  test_the_aws_profile_is_shown_only_when_set
scenario_run 'a terminal gets the git segment after the prompt' \
  test_a_terminal_gets_the_git_segment_after_the_prompt

scenario_finish
