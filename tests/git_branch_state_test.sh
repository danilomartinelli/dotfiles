#!/usr/bin/env bash

set -euo pipefail

TEST_PATH=${BASH_SOURCE[0]}
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$(dirname -- "$TEST_PATH")/.." && pwd)
BRANCH_STATE_MODULE=$REPOSITORY_ROOT/git/_branch-state.sh
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-git-branch-state-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  local expected=$1 actual=$2 description=$3
  [[ $actual == "$expected" ]] || \
    fail "$description (expected '$expected', got '$actual')"
}

assert_contains() {
  local file=$1 expected=$2
  grep -Fq -- "$expected" "$file" || \
    fail "Expected $file to contain: $expected"
}

assert_not_contains() {
  local file=$1 unexpected=$2
  if grep -Fq -- "$unexpected" "$file"; then
    fail "Expected $file not to contain: $unexpected"
  fi
}

assert_ref_exists() {
  local repository=$1 ref=$2
  git -C "$repository" show-ref --verify --quiet "$ref" || \
    fail "Expected $repository to contain ref $ref"
}

assert_ref_missing() {
  local repository=$1 ref=$2
  if git -C "$repository" show-ref --verify --quiet "$ref"; then
    fail "Expected $repository not to contain ref $ref"
  fi
}

capture_status() {
  set +e
  "$@"
  CAPTURED_STATUS=$?
  set -e
}

new_fixture() {
  FIXTURE=$(mktemp -d "$TEST_ROOT/fixture.XXXXXX")
  WORKTREE=$FIXTURE/worktree
  ORIGIN=$FIXTURE/origin.git
  TEST_HOME=$FIXTURE/home
  FAKE_BIN=$FIXTURE/fake-bin
  STDOUT_LOG=$FIXTURE/stdout.log
  STDERR_LOG=$FIXTURE/stderr.log
  PBCOPY_CAPTURE=$FIXTURE/pbcopy.txt

  mkdir -p "$WORKTREE" "$TEST_HOME" "$FAKE_BIN"
  git -C "$WORKTREE" init -q
  git -C "$WORKTREE" symbolic-ref HEAD refs/heads/main
  git -C "$WORKTREE" config user.name 'Branch State Test'
  git -C "$WORKTREE" config user.email 'branch-state@example.invalid'
  git -C "$WORKTREE" config commit.gpgsign false

  printf '%s\n' initial > "$WORKTREE/tracked.txt"
  git -C "$WORKTREE" add tracked.txt
  git -C "$WORKTREE" commit -qm 'initial commit'

  git init --bare -q "$ORIGIN"
  git -C "$WORKTREE" remote add origin "$ORIGIN"
  git -C "$WORKTREE" push -qu origin main

  cat > "$FAKE_BIN/pbcopy" <<'EOF'
#!/bin/sh
cat > "$PBCOPY_CAPTURE"
EOF
  chmod +x "$FAKE_BIN/pbcopy"
}

create_commit() {
  local name=$1 content=$2
  printf '%s\n' "$content" > "$WORKTREE/$name"
  git -C "$WORKTREE" add "$name"
  git -C "$WORKTREE" commit -qm "add $name"
}

query_state_at() {
  local directory=$1 operation=$2
  shift 2

  (
    cd "$directory"
    # shellcheck disable=SC1090 # The module path is resolved at runtime.
    . "$BRANCH_STATE_MODULE"
    "$operation" git "$@"
  )
}

invoke_adapter_at() {
  local directory=$1 adapter=$2
  shift 2

  (
    cd "$directory"
    HOME=$TEST_HOME \
      PATH="$FAKE_BIN:$PATH" \
      PBCOPY_CAPTURE=$PBCOPY_CAPTURE \
      "$REPOSITORY_ROOT/bin/$adapter" "$@"
  ) > "$STDOUT_LOG" 2> "$STDERR_LOG"
}

invoke_adapter() {
  local adapter=$1
  shift
  invoke_adapter_at "$WORKTREE" "$adapter" "$@"
}

invoke_need_push() {
  (
    cd "$WORKTREE"
    HOME=$TEST_HOME DOTFILES_ROOT=$REPOSITORY_ROOT zsh -d -f -c '
      autoload -U colors
      colors
      source "$DOTFILES_ROOT/zsh/prompt.zsh"
      need_push
    '
  ) > "$STDOUT_LOG" 2> "$STDERR_LOG"
}

test_branch_state_contract() {
  local branch remote_offline

  new_fixture

  branch=$(query_state_at "$WORKTREE" _dotfiles_git_state_current_branch)
  assert_equal main "$branch" 'current branch'

  capture_status query_state_at "$FIXTURE" \
    _dotfiles_git_state_require_worktree > "$STDOUT_LOG" 2> "$STDERR_LOG"
  assert_equal 1 "$CAPTURED_STATUS" 'non-worktree status'
  assert_contains "$STDERR_LOG" 'Error: Not in a git repository.'

  git -C "$WORKTREE" checkout --detach -q
  capture_status query_state_at "$WORKTREE" \
    _dotfiles_git_state_current_branch > "$STDOUT_LOG" 2> "$STDERR_LOG"
  assert_equal 1 "$CAPTURED_STATUS" 'detached HEAD status'
  assert_contains "$STDERR_LOG" 'Error: Not on a branch (detached HEAD state).'
  git -C "$WORKTREE" switch -q main

  git -C "$WORKTREE" branch candidate-long
  git -C "$WORKTREE" push -q origin candidate-long
  capture_status query_state_at "$WORKTREE" \
    _dotfiles_git_state_live_origin_branch_exists candidate \
    > "$STDOUT_LOG" 2> "$STDERR_LOG"
  assert_equal 1 "$CAPTURED_STATUS" 'exact missing live branch status'
  query_state_at "$WORKTREE" \
    _dotfiles_git_state_live_origin_branch_exists candidate-long

  git -C "$WORKTREE" update-ref -d refs/remotes/origin/main
  capture_status query_state_at "$WORKTREE" \
    _dotfiles_git_state_origin_tracking_branch_exists main
  assert_equal 1 "$CAPTURED_STATUS" 'missing cached origin status'
  query_state_at "$WORKTREE" _dotfiles_git_state_live_origin_branch_exists main

  git -C "$WORKTREE" update-ref refs/remotes/origin/ghost HEAD
  query_state_at "$WORKTREE" \
    _dotfiles_git_state_origin_tracking_branch_exists ghost
  capture_status query_state_at "$WORKTREE" \
    _dotfiles_git_state_live_origin_branch_exists ghost
  assert_equal 1 "$CAPTURED_STATUS" 'missing live origin status'

  remote_offline=$FIXTURE/origin-offline.git
  mv "$ORIGIN" "$remote_offline"
  capture_status query_state_at "$WORKTREE" \
    _dotfiles_git_state_live_origin_branch_exists main \
    > "$STDOUT_LOG" 2> "$STDERR_LOG"
  assert_equal 2 "$CAPTURED_STATUS" 'unavailable live origin status'
  assert_contains "$STDERR_LOG" "Error: Unable to query origin for branch 'main'."
}

test_current_branch_adapter_errors() {
  local adapter

  new_fixture
  git -C "$WORKTREE" checkout --detach -q

  for adapter in \
    git-promote git-track git-unpushed git-unpushed-stat git-copy-branch-name
  do
    capture_status invoke_adapter "$adapter"
    assert_equal 1 "$CAPTURED_STATUS" "$adapter detached HEAD status"
    assert_contains "$STDERR_LOG" 'Error: Not on a branch (detached HEAD state).'
  done

  capture_status invoke_adapter_at "$FIXTURE" git-nuke topic
  assert_equal 1 "$CAPTURED_STATUS" 'git-nuke non-worktree status'
  assert_contains "$STDERR_LOG" 'Error: Not in a git repository.'
}

test_promote_and_track() {
  local remote_offline

  new_fixture
  git -C "$WORKTREE" switch -qc topic
  create_commit topic.txt 'topic change'
  git -C "$WORKTREE" config branch.topic.remote elsewhere
  git -C "$WORKTREE" config branch.topic.merge refs/heads/elsewhere

  invoke_adapter git-promote
  assert_contains "$STDOUT_LOG" "Pushing branch 'topic' to origin..."
  assert_ref_exists "$ORIGIN" refs/heads/topic
  assert_equal origin \
    "$(git -C "$WORKTREE" config --get branch.topic.remote)" \
    'promoted branch remote'
  assert_equal refs/heads/topic \
    "$(git -C "$WORKTREE" config --get branch.topic.merge)" \
    'promoted branch merge ref'

  invoke_adapter git-promote
  assert_not_contains "$STDOUT_LOG" "Pushing branch 'topic' to origin..."

  git -C "$WORKTREE" switch -q main
  git -C "$WORKTREE" branch track-me
  git -C "$WORKTREE" push -q origin track-me
  git -C "$WORKTREE" switch -q track-me
  git -C "$WORKTREE" config --unset-all branch.track-me.remote || true
  git -C "$WORKTREE" config --unset-all branch.track-me.merge || true

  remote_offline=$FIXTURE/origin-offline.git
  mv "$ORIGIN" "$remote_offline"
  invoke_adapter git-track
  assert_equal origin \
    "$(git -C "$WORKTREE" config --get branch.track-me.remote)" \
    'offline tracking remote'
  assert_equal refs/heads/track-me \
    "$(git -C "$WORKTREE" config --get branch.track-me.merge)" \
    'offline tracking merge ref'

  git -C "$WORKTREE" update-ref -d refs/remotes/origin/track-me
  capture_status invoke_adapter git-track
  assert_equal 1 "$CAPTURED_STATUS" 'missing cached track branch status'
  assert_contains "$STDERR_LOG" \
    "Remote-tracking branch 'origin/track-me' is not available locally. Run 'git fetch origin'."
}

test_unpushed_copy_and_prompt() {
  local copied count

  new_fixture
  count=$(query_state_at "$WORKTREE" _dotfiles_git_state_ahead_count main)
  assert_equal 0 "$count" 'zero ahead count'
  invoke_adapter git-unpushed-stat
  assert_contains "$STDOUT_LOG" '0 commits total'

  create_commit one.txt 'first unpushed line'

  invoke_adapter git-unpushed
  assert_contains "$STDOUT_LOG" '+first unpushed line'

  invoke_adapter git-unpushed-stat
  assert_contains "$STDOUT_LOG" '1 commit total'

  create_commit two.txt 'second unpushed line'
  invoke_adapter git-unpushed-stat
  assert_contains "$STDOUT_LOG" '2 commits total'

  invoke_adapter git-copy-branch-name
  assert_equal main "$(tr -d '\n' < "$STDOUT_LOG")" 'copied branch stdout'
  copied=$(< "$PBCOPY_CAPTURE")
  assert_equal main "$copied" 'pbcopy branch content'

  mv "$ORIGIN" "$FIXTURE/origin-offline.git"
  invoke_adapter git-unpushed
  assert_contains "$STDOUT_LOG" '+second unpushed line'
  invoke_adapter git-unpushed-stat
  assert_contains "$STDOUT_LOG" '2 commits total'
  invoke_need_push
  assert_contains "$STDOUT_LOG" '2 unpushed'

  git -C "$WORKTREE" update-ref -d refs/remotes/origin/main
  capture_status invoke_adapter git-unpushed
  assert_equal 1 "$CAPTURED_STATUS" 'missing cached unpushed branch status'
  assert_contains "$STDERR_LOG" \
    "Remote-tracking branch 'origin/main' is not available locally. Run 'git fetch origin'."

  invoke_need_push
  [[ ! -s $STDOUT_LOG ]] || fail 'Prompt should be quiet without a cached origin ref'

  git -C "$WORKTREE" checkout --detach -q
  invoke_need_push
  [[ ! -s $STDOUT_LOG ]] || fail 'Prompt should be quiet in detached HEAD state'
}

test_nuke() {
  new_fixture
  git -C "$WORKTREE" branch doomed
  git -C "$WORKTREE" push -q origin doomed

  invoke_adapter git-nuke doomed
  assert_ref_missing "$WORKTREE" refs/heads/doomed
  assert_ref_missing "$ORIGIN" refs/heads/doomed

  invoke_adapter git-nuke absent
  assert_contains "$STDERR_LOG" "Warning: Branch 'absent' does not exist locally."
  assert_contains "$STDERR_LOG" "Info: Branch 'absent' does not exist on origin."
}

test_branch_state_contract
echo 'ok 1 - branch-state queries distinguish repository, ref, and remote states'
test_current_branch_adapter_errors
echo 'ok 2 - current-branch adapters reject detached HEAD consistently'
test_promote_and_track
echo 'ok 3 - promote and track enforce matching origin state'
test_unpushed_copy_and_prompt
echo 'ok 4 - unpushed commands, clipboard, and prompt share cached state'
test_nuke
echo 'ok 5 - nuke deletes exact local and live origin branches'
echo '1..5'
