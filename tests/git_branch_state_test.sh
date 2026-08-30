#!/usr/bin/env bash

set -u

TEST_PATH=${BASH_SOURCE[0]}
TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$TEST_PATH")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
BRANCH_STATE_MODULE=$REPOSITORY_ROOT/git/_branch-state.sh
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-git-branch-state-tests
TEST_ROOT=$SCENARIO_ROOT

# Git refs are this suite's own vocabulary; everything else it asserts comes
# from the shared harness.
assert_ref_exists() {
  local repository=$1 ref=$2
  git -C "$repository" show-ref --verify --quiet "$ref" \
    || scenario_fail "Expected $repository to contain ref $ref"
}

assert_ref_missing() {
  local repository=$1 ref=$2
  if git -C "$repository" show-ref --verify --quiet "$ref"; then
    scenario_fail "Expected $repository not to contain ref $ref"
  fi
}

# Several cases assert both the status and what was printed, so the status is
# captured rather than asserted in place.
capture_status() {
  CAPTURED_STATUS=0
  "$@" || CAPTURED_STATUS=$?
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

  printf '%s\n' initial >"$WORKTREE/tracked.txt"
  git -C "$WORKTREE" add tracked.txt
  git -C "$WORKTREE" commit -qm 'initial commit'

  git init --bare -q "$ORIGIN"
  git -C "$WORKTREE" remote add origin "$ORIGIN"
  git -C "$WORKTREE" push -qu origin main

  cat >"$FAKE_BIN/pbcopy" <<'EOF'
#!/bin/sh
cat > "$PBCOPY_CAPTURE"
EOF
  chmod +x "$FAKE_BIN/pbcopy"
}

create_commit() {
  local name=$1 content=$2
  printf '%s\n' "$content" >"$WORKTREE/$name"
  git -C "$WORKTREE" add "$name"
  git -C "$WORKTREE" commit -qm "add $name"
}

query_state_at() {
  local directory=$1 operation=$2
  shift 2

  (
    cd "$directory" || exit 1
    # shellcheck disable=SC1090 # The module path is resolved at runtime.
    . "$BRANCH_STATE_MODULE"
    "$operation" git "$@"
  )
}

invoke_adapter_at() {
  local directory=$1 adapter=$2
  shift 2

  (
    cd "$directory" || exit 1
    HOME=$TEST_HOME \
      PATH="$FAKE_BIN:$PATH" \
      PBCOPY_CAPTURE=$PBCOPY_CAPTURE \
      "$REPOSITORY_ROOT/bin/$adapter" "$@"
  ) >"$STDOUT_LOG" 2>"$STDERR_LOG"
}

invoke_adapter() {
  local adapter=$1
  shift
  invoke_adapter_at "$WORKTREE" "$adapter" "$@"
}

invoke_need_push() {
  (
    cd "$WORKTREE" || exit 1
    HOME=$TEST_HOME DOTFILES_ROOT=$REPOSITORY_ROOT zsh -d -f -c '
      autoload -U colors
      colors
      source "$DOTFILES_ROOT/zsh/prompt.zsh"
      need_push
    '
  ) >"$STDOUT_LOG" 2>"$STDERR_LOG"
}

test_branch_state_contract() {
  local branch remote_offline

  new_fixture

  branch=$(query_state_at "$WORKTREE" _dotfiles_git_state_current_branch)
  assert_equal main "$branch" 'current branch'

  capture_status query_state_at "$FIXTURE" \
    _dotfiles_git_state_require_worktree >"$STDOUT_LOG" 2>"$STDERR_LOG"
  assert_equal 1 "$CAPTURED_STATUS" 'non-worktree status'
  assert_contains "$STDERR_LOG" 'Error: Not in a git repository.'

  git -C "$WORKTREE" checkout --detach -q
  capture_status query_state_at "$WORKTREE" \
    _dotfiles_git_state_current_branch >"$STDOUT_LOG" 2>"$STDERR_LOG"
  assert_equal 1 "$CAPTURED_STATUS" 'detached HEAD status'
  assert_contains "$STDERR_LOG" 'Error: Not on a branch (detached HEAD state).'
  branch=$(query_state_at "$WORKTREE" _dotfiles_git_state_current_branch_or_empty)
  assert_equal '' "$branch" 'detached HEAD empty branch'
  git -C "$WORKTREE" switch -q main
  branch=$(query_state_at "$WORKTREE" _dotfiles_git_state_current_branch_or_empty)
  assert_equal main "$branch" 'current branch or empty on branch'

  git -C "$WORKTREE" branch candidate-long
  git -C "$WORKTREE" push -q origin candidate-long
  capture_status query_state_at "$WORKTREE" \
    _dotfiles_git_state_live_origin_branch_exists candidate \
    >"$STDOUT_LOG" 2>"$STDERR_LOG"
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
    >"$STDOUT_LOG" 2>"$STDERR_LOG"
  assert_equal 2 "$CAPTURED_STATUS" 'unavailable live origin status'
  assert_contains "$STDERR_LOG" "Error: Unable to query origin for branch 'main'."
}

test_current_branch_adapter_errors() {
  local adapter

  new_fixture
  git -C "$WORKTREE" checkout --detach -q

  for adapter in \
    git-promote git-track git-unpushed git-unpushed-stat git-copy-branch-name; do
    capture_status invoke_adapter "$adapter"
    assert_equal 1 "$CAPTURED_STATUS" "$adapter detached HEAD status"
    assert_contains "$STDERR_LOG" 'Error: Not on a branch (detached HEAD state).'
  done

  capture_status invoke_adapter_at "$FIXTURE" git-nuke topic
  assert_equal 1 "$CAPTURED_STATUS" 'git-nuke non-worktree status'
  assert_contains "$STDERR_LOG" 'Error: Not in a git repository.'
}

# The Git directory is the case the hand-rolled guards got wrong: `rev-parse
# --git-dir` succeeds there, so an adapter checking it would stage or pull
# from inside .git while every adapter crossing the seam refused.
test_worktree_guard_covers_the_git_directory() {
  local adapter

  new_fixture

  for adapter in git-all git-amend git-credit git-edit-new git-up git-undo; do
    capture_status invoke_adapter_at "$WORKTREE/.git" "$adapter" name email
    assert_equal 1 "$CAPTURED_STATUS" "$adapter Git-directory status"
    assert_contains "$STDERR_LOG" 'Error: Not in a git repository.'
  done

  # A tree that is no repository at all reaches the same refusal.
  for adapter in git-all git-amend git-credit git-edit-new git-up git-undo; do
    capture_status invoke_adapter_at "$FIXTURE" "$adapter" name email
    assert_equal 1 "$CAPTURED_STATUS" "$adapter non-repository status"
    assert_contains "$STDERR_LOG" 'Error: Not in a git repository.'
  done

  # The guard refuses without touching the work tree it was pointed away from.
  assert_equal 'initial' "$(command cat "$WORKTREE/tracked.txt")" \
    'guarded adapters leave the work tree alone'
}

# Passing the guard must still reach the adapter's own work.
test_guarded_adapters_run_inside_a_worktree() {
  new_fixture

  printf '%s\n' untracked >"$WORKTREE/new.txt"
  invoke_adapter git-all
  git -C "$WORKTREE" diff --cached --name-only | grep -q new.txt \
    || scenario_fail 'git-all did not stage the new file'

  git -C "$WORKTREE" commit -qm 'stage everything'
  invoke_adapter git-undo
  git -C "$WORKTREE" diff --cached --name-only | grep -q new.txt \
    || scenario_fail 'git-undo did not restore the staged change'
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
  assert_equal main "$(tr -d '\n' <"$STDOUT_LOG")" 'copied branch stdout'
  copied=$(<"$PBCOPY_CAPTURE")
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
  [[ ! -s $STDOUT_LOG ]] || scenario_fail 'Prompt should be quiet without a cached origin ref'

  git -C "$WORKTREE" checkout --detach -q
  invoke_need_push
  [[ ! -s $STDOUT_LOG ]] || scenario_fail 'Prompt should be quiet in detached HEAD state'
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

scenario_run 'branch-state queries distinguish repository, ref, and remote states' \
  test_branch_state_contract
scenario_run 'current-branch adapters reject detached HEAD consistently' \
  test_current_branch_adapter_errors
scenario_run 'promote and track enforce matching origin state' \
  test_promote_and_track
scenario_run 'unpushed commands, clipboard, and prompt share cached state' \
  test_unpushed_copy_and_prompt
scenario_run 'nuke deletes exact local and live origin branches' test_nuke
scenario_run 'every command adapter refuses outside a work tree' \
  test_worktree_guard_covers_the_git_directory
scenario_run 'guarded adapters still do their work inside a work tree' \
  test_guarded_adapters_run_inside_a_worktree
scenario_finish
