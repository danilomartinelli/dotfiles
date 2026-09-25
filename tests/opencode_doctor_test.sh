#!/usr/bin/env bash

set -u

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
scenario_init dotfiles-opencode-doctor-tests

DOCTOR=$REPOSITORY_ROOT/opencode/_doctor.sh

# The module asks lsof which processes hold the database and which ones still
# sit inside a worktree, and both answers are about the live process table. So
# the fixture spawns its own harmless processes and lets the real lsof find
# them, rather than teaching a stub to imitate two output formats. Every
# process it starts lives under the fixture, so the reaping under test can
# only reach what the test created. lsof is in /usr/sbin, which the shared
# fixture PATH does not carry.
FIXTURE_PATH_SUFFIX=/usr/bin:/bin:/usr/sbin

# Four sessions, each with the events and the sequence row the module reads:
# one inside the retention window still owed a reply, one whose reply was cut
# off before completion, one whose newest message is a completed reply, and one
# long past the window. The schema is the subset of OpenCode's that the module
# touches, with the foreign key that makes the event log cascade the way the
# real one does and the message shape the finished-session rule inspects.
make_fixture() {
  local fixture now recent stale artifact_root snapshot
  fixture=$(installer_fixture opencode-doctor)
  now=$(($(date +%s) * 1000))
  recent=$now
  stale=$((now - 30 * 86400 * 1000))

  mkdir -p "$fixture/data/log" "$fixture/config" \
    "$fixture/data/worktree/project/live-worktree"

  # Three delegation artifact directories under the live worktree: one written
  # to just now, one untouched for a month, and one holding a file large enough
  # to be named individually. Loose evidence sits in the artifact root, which
  # belongs to no delegation and must survive every repair.
  # Three session snapshots: one shadowing the live worktree, one whose
  # directory is gone, and one whose config names no worktree at all and so
  # cannot be judged.
  for snapshot in live lost unset; do
    git -c init.defaultBranch=main init --quiet --bare \
      "$fixture/data/snapshot/project/$snapshot"
  done
  git --git-dir "$fixture/data/snapshot/project/live" config \
    core.worktree "$fixture/data/worktree/project/live-worktree"
  git --git-dir "$fixture/data/snapshot/project/lost" config \
    core.worktree "$fixture/data/worktree/project/gone"

  artifact_root=$fixture/data/worktree/project/live-worktree/.opencode-artifacts
  mkdir -p "$artifact_root/fresh" "$artifact_root/idle" "$artifact_root/bulky"
  printf 'evidence\n' >"$artifact_root/loose-evidence.log"
  printf 'evidence\n' >"$artifact_root/fresh/screenshot.png"
  printf 'evidence\n' >"$artifact_root/idle/screenshot.png"
  dd if=/dev/zero of="$artifact_root/bulky/derived-data.bin" bs=1024 count=64 \
    2>/dev/null
  touch -t "$(date -r $((now / 1000 - 30 * 86400)) +%Y%m%d%H%M)" \
    "$artifact_root/idle/screenshot.png" "$artifact_root/idle"

  sqlite3 "$fixture/data/opencode.db" <<EOF
CREATE TABLE session (
  id text PRIMARY KEY,
  workspace_id text,
  time_updated integer NOT NULL
);
CREATE TABLE message (
  id text PRIMARY KEY,
  session_id text NOT NULL,
  time_created integer NOT NULL,
  data text NOT NULL
);
CREATE TABLE event_sequence (aggregate_id text PRIMARY KEY, seq integer NOT NULL);
CREATE TABLE event (
  id text PRIMARY KEY,
  aggregate_id text NOT NULL,
  seq integer NOT NULL,
  type text NOT NULL,
  data text NOT NULL,
  CONSTRAINT fk_event FOREIGN KEY (aggregate_id)
    REFERENCES event_sequence (aggregate_id) ON DELETE CASCADE
);
CREATE TABLE workspace (
  id text PRIMARY KEY,
  type text NOT NULL,
  name text NOT NULL,
  directory text,
  project_id text NOT NULL,
  time_used integer NOT NULL
);

INSERT INTO session VALUES
  ('ses_recent', NULL, $recent), ('ses_cut', NULL, $recent),
  ('ses_done', 'wrk_live', $recent), ('ses_stale', 'wrk_gone', $stale);
INSERT INTO message VALUES
  ('msg_r1', 'ses_recent', 1, '{"role":"assistant","time":{"created":1,"completed":2}}'),
  ('msg_r2', 'ses_recent', 2, '{"role":"user","time":{"created":2}}'),
  ('msg_c1', 'ses_cut', 1, '{"role":"user","time":{"created":1}}'),
  ('msg_c2', 'ses_cut', 2, '{"role":"assistant","time":{"created":2}}'),
  ('msg_d1', 'ses_done', 1, '{"role":"user","time":{"created":1}}'),
  ('msg_d2', 'ses_done', 2, '{"role":"assistant","time":{"created":2,"completed":3}}'),
  ('msg_s1', 'ses_stale', 1, '{"role":"user","time":{"created":1}}');
INSERT INTO event_sequence VALUES
  ('ses_recent', 2), ('ses_cut', 1), ('ses_done', 2), ('ses_stale', 3);
INSERT INTO event VALUES
  ('evt_r1', 'ses_recent', 1, 'message.part.updated.1', '{}'),
  ('evt_r2', 'ses_recent', 2, 'message.part.updated.1', '{}'),
  ('evt_c1', 'ses_cut', 1, 'message.part.updated.1', '{}'),
  ('evt_d1', 'ses_done', 1, 'message.part.updated.1', '{}'),
  ('evt_d2', 'ses_done', 2, 'message.part.updated.1', '{}'),
  ('evt_s1', 'ses_stale', 1, 'message.part.updated.1', '{}'),
  ('evt_s2', 'ses_stale', 2, 'message.part.updated.1', '{}'),
  ('evt_s3', 'ses_stale', 3, 'message.part.updated.1', '{}');
INSERT INTO workspace VALUES
  ('wrk_live', 'worktree', 'live', '$fixture/data/worktree/project/live-worktree', 'project', 1),
  ('wrk_lost', 'ocx-git-worktree', 'lost', '$fixture/data/worktree/project/gone', 'project', 1);
-- ses_stale names a workspace that was never inserted, the shape that strands
-- a session: its delete and archive both fail before they reach the session.
EOF

  printf '%s\n' "$fixture"
}

# The shared PATH is overridden rather than replaced at the fixture level: the
# later assignment wins in env, so this adds /usr/sbin without teaching every
# other suite about lsof.
invoke_doctor() {
  local fixture=$1
  shift
  local -a artifacts=()
  local -a overrides=()

  if [ "${1-}" = --artifacts ]; then
    artifacts=(--artifacts "$2")
    shift 2
  fi

  # Same contract as fixture_run: a leading KEY=value is the module's
  # environment, not one of its arguments.
  while [ "$#" -gt 0 ]; do
    case $1 in
      [A-Z_]*=*)
        overrides+=("$1")
        shift
        ;;
      *) break ;;
    esac
  done

  fixture_run "$fixture" ${artifacts[@]+"${artifacts[@]}"} \
    ${overrides[@]+"${overrides[@]}"} \
    PATH="$fixture/fake-bin:$FIXTURE_PATH_SUFFIX" \
    -- "$DOCTOR" \
    --data-dir "$fixture/data" \
    --config-dir "$fixture/config" \
    "$@"
}

# lsof reads the live process table, so a process the test just started has to
# be visible there before the module's answer about it means anything.
wait_until_listed() {
  local probe_directory=$1
  local waited=0

  while [ "$waited" -lt 50 ]; do
    lsof -d cwd -Fn 2>/dev/null | grep -Fq -- "n$probe_directory" && return 0
    sleep 0.1
    waited=$((waited + 1))
  done
  scenario_fail "process never became visible to lsof in $probe_directory"
}

count_rows() {
  sqlite3 "$1/data/opencode.db" "$2"
}

# A process whose working directory is the given one, kept alive long enough
# for the module to see it and short enough that a failed test cannot leave it
# behind. Its pid is printed so the test can stop it either way.
#
# The output redirection is load-bearing: this runs inside a command
# substitution, which waits for the write end of its pipe to close, and a
# background child that inherited it would hold the caller for the full sleep.
spawn_process_in() {
  local directory=$1

  (
    cd "$directory" || exit 1
    exec sleep 120
  ) >/dev/null 2>&1 &
  printf '%s\n' "$!"
}

stop_process() {
  kill -KILL "$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
}

test_report_names_state_without_changing_it() {
  local fixture
  fixture=$(make_fixture)
  invoke_doctor "$fixture"

  assert_contains "$fixture/stdout.log" \
    'prunable replication events (finished sessions, or idle for 7 days): 5'
  assert_contains "$fixture/stdout.log" 'wrk_lost'
  assert_not_contains "$fixture/stdout.log" 'wrk_live'
  assert_equal '8' "$(count_rows "$fixture" 'SELECT count(*) FROM event;')" \
    'events after a report'
  assert_equal '2' "$(count_rows "$fixture" 'SELECT count(*) FROM workspace;')" \
    'workspace rows after a report'
}

test_untracked_shadowing_config_is_reported() {
  local fixture
  fixture=$(make_fixture)
  : >"$fixture/config/opencode.jsonc"
  : >"$fixture/config/opencode.json"
  : >"$fixture/config/opencode.jsonc.desktop.backup"
  invoke_doctor "$fixture"

  assert_contains "$fixture/stderr.log" "$fixture/config/opencode.json"
  assert_contains "$fixture/stderr.log" "$fixture/config/opencode.jsonc.desktop.backup"
}

test_clean_config_directory_is_not_reported() {
  local fixture
  fixture=$(make_fixture)
  : >"$fixture/config/opencode.jsonc"
  invoke_doctor "$fixture"

  assert_contains "$fixture/stdout.log" 'no untracked configuration shadows a managed entry'
  assert_empty "$fixture/stderr.log"
}

test_fix_prunes_finished_and_stale_sessions_only() {
  local fixture
  fixture=$(make_fixture)
  invoke_doctor "$fixture" --fix

  assert_equal '3' "$(count_rows "$fixture" 'SELECT count(*) FROM event;')" \
    'events kept after a repair'
  assert_equal '0' \
    "$(count_rows "$fixture" "SELECT count(*) FROM event WHERE aggregate_id = 'ses_stale';")" \
    'stale events after a repair'
  assert_equal '0' \
    "$(count_rows "$fixture" "SELECT count(*) FROM event WHERE aggregate_id = 'ses_done';")" \
    'events of a finished session after a repair'
  assert_equal '2' \
    "$(count_rows "$fixture" "SELECT count(*) FROM event WHERE aggregate_id = 'ses_recent';")" \
    'events of a session still owed a reply'
  assert_equal '1' \
    "$(count_rows "$fixture" "SELECT count(*) FROM event WHERE aggregate_id = 'ses_cut';")" \
    'events of a session whose reply was cut off'
  assert_contains "$fixture/stdout.log" \
    'pruned replication events of finished sessions and of sessions idle for 7 days'
}

# The window only protects unfinished sessions: widening it keeps the stale
# one, and the finished one goes regardless.
test_retention_window_is_selectable() {
  local fixture
  fixture=$(make_fixture)
  invoke_doctor "$fixture" --fix --days 60

  assert_equal '6' "$(count_rows "$fixture" 'SELECT count(*) FROM event;')" \
    'events kept by a wider window'
  assert_equal '3' \
    "$(count_rows "$fixture" "SELECT count(*) FROM event WHERE aggregate_id = 'ses_stale';")" \
    'stale events inside a wider window'
  assert_equal '0' \
    "$(count_rows "$fixture" "SELECT count(*) FROM event WHERE aggregate_id = 'ses_done';")" \
    'events of a finished session inside a wider window'
}

# Deleting or archiving resolves the workspace first, so a reference to a row
# that is gone strands the session in the UI with no way out.
test_report_names_sessions_whose_workspace_is_gone() {
  local fixture
  fixture=$(make_fixture)
  invoke_doctor "$fixture"

  assert_contains "$fixture/stdout.log" \
    'sessions that cannot be deleted or archived, their workspace row gone: 1'
  assert_equal 'wrk_gone' \
    "$(count_rows "$fixture" "SELECT workspace_id FROM session WHERE id = 'ses_stale';")" \
    'workspace reference after a report'
}

# The repair leaves the session exactly as one opened without a workspace, which
# deletes normally; a live reference is untouched.
test_fix_releases_only_sessions_whose_workspace_is_gone() {
  local fixture
  fixture=$(make_fixture)
  invoke_doctor "$fixture" --fix

  assert_equal '' \
    "$(count_rows "$fixture" "SELECT ifnull(workspace_id, '') FROM session WHERE id = 'ses_stale';")" \
    'stranded workspace reference after a repair'
  assert_equal 'wrk_live' \
    "$(count_rows "$fixture" "SELECT workspace_id FROM session WHERE id = 'ses_done';")" \
    'live workspace reference after a repair'
  assert_contains "$fixture/stdout.log" \
    'released 1 session(s) whose workspace row was gone'
}

test_report_names_snapshots_whose_directory_is_gone() {
  local fixture
  fixture=$(make_fixture)
  invoke_doctor "$fixture"

  assert_contains "$fixture/stdout.log" 'session snapshots whose directory is gone: 1'
  assert_contains "$fixture/stdout.log" "snapshot lost $fixture/data/worktree/project/gone"
  [ -d "$fixture/data/snapshot/project/lost" ] \
    || scenario_fail 'a report must not remove a snapshot'
}

test_fix_removes_only_snapshots_whose_directory_is_gone() {
  local fixture
  fixture=$(make_fixture)
  invoke_doctor "$fixture" --fix

  [ ! -e "$fixture/data/snapshot/project/lost" ] \
    || scenario_fail 'a snapshot describing a missing directory survived'
  [ -d "$fixture/data/snapshot/project/live" ] \
    || scenario_fail 'a snapshot shadowing a live directory was removed'
  [ -d "$fixture/data/snapshot/project/unset" ] \
    || scenario_fail 'a snapshot naming no worktree was removed'
  assert_contains "$fixture/stdout.log" \
    'removed 1 session snapshot(s) describing a missing directory'
}

# Three agent worktree checkouts beside the fixture's existing non-Git one:
# one reconstructible (clean and fully pushed to a bare origin), one holding a
# commit the origin has never seen, and one holding an uncommitted change. The
# origin is a real bare repository rather than a stub, because the whole
# question the condition asks -- does every byte here exist somewhere else --
# is one only Git can answer.
#
# Their mtimes are pushed a month back so the default retention window treats
# them as idle; the `live-worktree` the other scenarios use stays untouched.
make_worktree_checkouts() {
  local fixture=$1 root checkout
  root=$fixture/data/worktree/project

  for checkout in pushed unpushed dirty 'spaced name'; do
    make_pushed_checkout "$fixture" "$checkout"
  done

  printf 'local only\n' >"$root/unpushed/file.txt"
  git -C "$root/unpushed" commit --quiet -am 'local only'
  printf 'uncommitted\n' >"$root/dirty/file.txt"

  for checkout in pushed unpushed dirty 'spaced name'; do
    backdate "$root/$checkout"
  done
}

# One clean clone under the worktree root, fully pushed to an origin of its
# own. Sharing a single bare repository made the second and third pushes
# non-fast-forward rejections, which left those checkouts holding work for a
# reason the scenario never meant to arrange.
make_pushed_checkout() {
  local fixture=$1 name=$2 checkout
  checkout=$fixture/data/worktree/project/$name

  git -c init.defaultBranch=main init --quiet --bare "$fixture/$name.git"
  git -c init.defaultBranch=main init --quiet "$checkout"
  git -C "$checkout" config user.email fixture@example.invalid
  git -C "$checkout" config user.name Fixture
  printf 'source\n' >"$checkout/file.txt"
  git -C "$checkout" add file.txt
  git -C "$checkout" commit --quiet -m 'fixture'
  git -C "$checkout" remote add origin "$fixture/$name.git"
  git -C "$checkout" push --quiet -u origin main
}

# Push every mtime in a tree a month back, so the default retention window
# treats it as idle. -depth so children are touched before their parents:
# touching a file inside a directory bumps that directory's own mtime back to
# now, and a single fresh entry anywhere keeps a checkout inside the window.
backdate() {
  find "$1" -depth -exec touch -h -t \
    "$(date -r $(($(date +%s) - 30 * 86400)) +%Y%m%d%H%M)" {} +
}

# A repository of the user's own, outside the data directory, and worktrees
# added from it: one agent checkout per name under the worktree root, each
# tracking the pushed branch, and a sibling of the user's outside the data
# directory that no repair may touch. The owner's exclude file keeps a
# delegation's artifacts out of every worktree's status.
make_linked_worktrees() {
  local fixture=$1 owner=$1/owner name
  shift

  git -c init.defaultBranch=main init --quiet --bare "$fixture/owner-origin.git"
  git -c init.defaultBranch=main init --quiet "$owner"
  git -C "$owner" config user.email fixture@example.invalid
  git -C "$owner" config user.name Fixture
  printf 'source\n' >"$owner/file.txt"
  git -C "$owner" add file.txt
  git -C "$owner" commit --quiet -m 'fixture'
  git -C "$owner" remote add origin "$fixture/owner-origin.git"
  git -C "$owner" push --quiet -u origin main
  mkdir -p "$owner/.git/info"
  printf '.opencode-artifacts/\n' >>"$owner/.git/info/exclude"

  git -C "$owner" worktree add --quiet --track -b sibling "$fixture/sibling" origin/main
  for name in "$@"; do
    git -C "$owner" worktree add --quiet --track -b "$name" \
      "$fixture/data/worktree/project/$name" origin/main
    backdate "$fixture/data/worktree/project/$name"
  done
}

# A delegation's artifact directory inside a checkout, kept out of that
# checkout's status the way the owner's exclude file keeps it for a worktree.
make_artifact() {
  local checkout=$1 name=$2 exclude
  exclude=$(git -C "$checkout" rev-parse --path-format=absolute --git-common-dir)/info/exclude

  mkdir -p "$(dirname -- "$exclude")" "$checkout/.opencode-artifacts/$name"
  grep -Fqx '.opencode-artifacts/' "$exclude" 2>/dev/null \
    || printf '.opencode-artifacts/\n' >>"$exclude"
  printf 'evidence\n' >"$checkout/.opencode-artifacts/$name/evidence.log"
}

# A snapshot, alone in a hash directory of its own, whose worktree is gone.
make_lost_snapshot() {
  local fixture=$1 hash=$2
  git -c init.defaultBranch=main init --quiet --bare "$fixture/data/snapshot/$hash/lost"
  git --git-dir "$fixture/data/snapshot/$hash/lost" config \
    core.worktree "$fixture/data/worktree/$hash/gone"
}

test_report_counts_artifacts_and_names_the_large_ones() {
  local fixture artifact_root
  fixture=$(make_fixture)
  artifact_root=$fixture/data/worktree/project/live-worktree/.opencode-artifacts
  invoke_doctor "$fixture" ARTIFACT_REPORT_BYTES=16384

  assert_contains "$fixture/stdout.log" 'delegation artifacts'
  assert_contains "$fixture/stdout.log" 'in 3 directory(ies)'
  # human_bytes formats through awk, whose decimal separator follows the
  # locale, so the assertion names the path rather than the rendered size.
  assert_contains "$fixture/stdout.log" "KB at $artifact_root/bulky"
  assert_not_contains "$fixture/stdout.log" "at $artifact_root/fresh"
  assert_contains "$fixture/stdout.log" 'retired artifacts (idle for 7 days): 1'
  [ -d "$artifact_root/idle" ] || scenario_fail 'a report must not retire anything'
}

# Only the directory nothing has written to since the window goes. Evidence
# sitting directly in the artifact root belongs to no delegation and stays.
test_fix_retires_only_idle_artifact_directories() {
  local fixture artifact_root
  fixture=$(make_fixture)
  artifact_root=$fixture/data/worktree/project/live-worktree/.opencode-artifacts
  invoke_doctor "$fixture" --fix

  [ ! -e "$artifact_root/idle" ] || scenario_fail 'an idle artifact directory survived'
  [ -e "$artifact_root/fresh/screenshot.png" ] || scenario_fail 'fresh evidence was retired'
  [ -e "$artifact_root/bulky/derived-data.bin" ] || scenario_fail 'a fresh large directory was retired'
  [ -e "$artifact_root/loose-evidence.log" ] || scenario_fail 'loose evidence was retired'
  assert_contains "$fixture/stdout.log" 'retired 1 delegation artifact directory(ies)'
}

test_days_zero_retires_every_artifact_directory() {
  local fixture artifact_root
  fixture=$(make_fixture)
  artifact_root=$fixture/data/worktree/project/live-worktree/.opencode-artifacts
  invoke_doctor "$fixture" --fix --days 0

  [ ! -e "$artifact_root/idle" ] || scenario_fail 'an idle artifact directory survived --days 0'
  [ ! -e "$artifact_root/fresh" ] || scenario_fail 'a fresh artifact directory survived --days 0'
  [ ! -e "$artifact_root/bulky" ] || scenario_fail 'a large artifact directory survived --days 0'
  [ -e "$artifact_root/loose-evidence.log" ] || scenario_fail 'loose evidence was retired'
}

test_fix_removes_only_workspaces_whose_directory_is_gone() {
  local fixture
  fixture=$(make_fixture)
  invoke_doctor "$fixture" --fix

  assert_equal '1' "$(count_rows "$fixture" 'SELECT count(*) FROM workspace;')" \
    'workspace rows after a repair'
  assert_equal 'wrk_live' \
    "$(count_rows "$fixture" 'SELECT id FROM workspace;')" \
    'surviving workspace row'
}

test_fix_reaps_a_process_left_inside_a_worktree() {
  local fixture pid
  fixture=$(make_fixture)
  pid=$(spawn_process_in "$fixture/data/worktree/project/live-worktree")
  wait_until_listed "$fixture/data/worktree/project/live-worktree"

  invoke_doctor "$fixture" --fix

  if kill -0 "$pid" 2>/dev/null; then
    stop_process "$pid"
    scenario_fail 'expected the process inside the worktree to be reaped'
    return 1
  fi
  wait "$pid" 2>/dev/null || true

  assert_contains "$fixture/stdout.log" 'reaped 1 process(es) left inside an agent worktree'
}

test_fix_refuses_while_the_database_is_held() {
  local fixture pid waited=0
  fixture=$(make_fixture)

  # A reader is enough: the module asks who has the file open, not who is
  # writing to it, because a live OpenCode is disqualifying either way.
  sh -c "exec 9<\"$fixture/data/opencode.db\"; exec sleep 120" &
  pid=$!

  while [ "$waited" -lt 50 ] && [ -z "$(lsof -t -- "$fixture/data/opencode.db" 2>/dev/null)" ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  printf 'keep live log\n' >"$fixture/data/log/opencode.log"
  assert_fails_with_status 1 invoke_doctor "$fixture" --fix --days 0 --clear-logs
  stop_process "$pid"

  assert_contains "$fixture/stderr.log" 'OpenCode is running and holds the database'
  assert_equal '8' "$(count_rows "$fixture" 'SELECT count(*) FROM event;')" \
    'events after a refused repair'
  assert_contains "$fixture/data/log/opencode.log" 'keep live log'
  [ -d "$fixture/data/snapshot/project/lost" ] || scenario_fail 'a refused repair removed a snapshot'
  [ -d "$fixture/data/worktree/project/live-worktree/.opencode-artifacts/fresh" ] \
    || scenario_fail 'a refused repair retired an artifact directory'
  assert_not_contains "$fixture/stdout.log" 'session snapshots'
}

test_zero_retention_and_log_clear_preserve_transcripts_and_other_files() {
  local fixture before
  fixture=$(make_fixture)
  # Also cover timestamps in the current second or ahead of the local clock.
  sqlite3 "$fixture/data/opencode.db" 'UPDATE session SET time_updated = 9999999999999;'
  before=$(count_rows "$fixture" 'SELECT id, session_id, time_created, data FROM message ORDER BY id;')
  printf 'today\n' >"$fixture/data/log/opencode.log"
  printf 'rotation\n' >"$fixture/data/log/opencode.log.1"
  printf 'plugin\n' >"$fixture/data/log/plugin.20260910.log"
  printf 'unrelated\n' >"$fixture/data/log/keep.txt"
  printf 'outside\n' >"$fixture/outside.log"
  ln -s "$fixture/outside.log" "$fixture/data/log/linked.log"
  mkdir "$fixture/data/log/directory.log"

  invoke_doctor "$fixture" --days 0 --clear-logs
  assert_equal '8' "$(count_rows "$fixture" 'SELECT count(*) FROM event;')" 'report preserves events'
  assert_contains "$fixture/data/log/opencode.log" 'today'

  invoke_doctor "$fixture" --fix --days 0 --clear-logs
  assert_equal '0' "$(count_rows "$fixture" 'SELECT count(*) FROM event;')" 'all replication events removed'
  assert_equal '4' "$(count_rows "$fixture" 'SELECT count(*) FROM session;')" 'sessions preserved'
  assert_equal '4' "$(count_rows "$fixture" 'SELECT count(*) FROM event_sequence;')" 'replication counters preserved'
  assert_equal "$before" "$(count_rows "$fixture" 'SELECT id, session_id, time_created, data FROM message ORDER BY id;')" 'transcripts unchanged'
  assert_equal 'ok' "$(count_rows "$fixture" 'PRAGMA integrity_check;')" 'database remains valid'
  [ ! -e "$fixture/data/log/opencode.log" ] || scenario_fail 'current log survived'
  [ ! -e "$fixture/data/log/opencode.log.1" ] || scenario_fail 'rotated log survived'
  [ ! -e "$fixture/data/log/plugin.20260910.log" ] || scenario_fail 'dated plugin log survived'
  assert_contains "$fixture/data/log/keep.txt" 'unrelated'
  assert_contains "$fixture/outside.log" 'outside'
  [ -L "$fixture/data/log/linked.log" ] || scenario_fail 'log symlink was removed'
  [ -d "$fixture/data/log/directory.log" ] || scenario_fail 'directory was removed'
  assert_contains "$fixture/stdout.log" 'cleared 3 log file(s)'

  invoke_doctor "$fixture" --fix --days 0 --clear-logs
  assert_contains "$fixture/stdout.log" 'cleared 0 log file(s)'
}

test_log_clear_refuses_a_symlinked_directory() {
  local fixture
  fixture=$(make_fixture)
  mv "$fixture/data/log" "$fixture/external-logs"
  printf 'outside\n' >"$fixture/external-logs/opencode.log"
  ln -s "$fixture/external-logs" "$fixture/data/log"
  assert_fails_with_status 1 invoke_doctor "$fixture" --fix --days 0 --clear-logs
  assert_contains "$fixture/external-logs/opencode.log" 'outside'
  assert_equal '8' "$(count_rows "$fixture" 'SELECT count(*) FROM event;')" 'preflight refusal preserves events'
}

test_repeat_repair_changes_nothing_further() {
  local fixture
  fixture=$(make_fixture)
  invoke_doctor "$fixture" --fix
  invoke_doctor "$fixture" --artifacts "$fixture/second" --fix

  assert_contains "$fixture/second/stdout.log" 'no prunable replication events'
  assert_equal '3' "$(count_rows "$fixture" 'SELECT count(*) FROM event;')" \
    'events after a repeated repair'
  assert_equal '1' "$(count_rows "$fixture" 'SELECT count(*) FROM workspace;')" \
    'workspace rows after a repeated repair'
}

test_oversized_log_is_rotated() {
  local fixture
  fixture=$(make_fixture)
  mkfile -n 65m "$fixture/data/log/opencode.log" 2>/dev/null \
    || dd if=/dev/zero of="$fixture/data/log/opencode.log" bs=1m count=65 2>/dev/null
  invoke_doctor "$fixture" --fix

  [ -f "$fixture/data/log/opencode.log.1" ] \
    || scenario_fail 'expected the oversized log to be rotated'
  [ ! -f "$fixture/data/log/opencode.log" ] \
    || scenario_fail 'expected the rotated log to be moved aside'
}

test_small_log_is_left_alone() {
  local fixture
  fixture=$(make_fixture)
  printf 'a log line\n' >"$fixture/data/log/opencode.log"
  invoke_doctor "$fixture" --fix

  [ ! -f "$fixture/data/log/opencode.log.1" ] \
    || scenario_fail 'expected a small log to be left in place'
  assert_contains "$fixture/data/log/opencode.log" 'a log line'
}

test_invalid_retention_is_a_usage_error() {
  local fixture
  fixture=$(make_fixture)
  assert_fails_with_status 2 invoke_doctor "$fixture" --days soon

  assert_contains "$fixture/stderr.log" '--days expects a whole number of days'
}

test_missing_database_is_an_operational_error() {
  local fixture
  fixture=$(make_fixture)
  rm -f "$fixture/data/opencode.db"
  assert_fails_with_status 1 invoke_doctor "$fixture"

  assert_contains "$fixture/stderr.log" 'no OpenCode database at'
}

# The CREATE TABLE script above is this suite's own, and opencode/_runtime-store.sh
# declares independently which tables and columns it reads. Neither derives the
# other, so they are held to each other here: a fixture that stopped covering
# the real dependency would otherwise let every scenario pass against a schema
# the module can no longer use.
test_fixture_schema_satisfies_the_store_declaration() {
  local fixture table columns column present
  fixture=$(make_fixture)

  while IFS=: read -r table columns; do
    [ -n "$table" ] || continue
    present=$(sqlite3 "$fixture/data/opencode.db" \
      "SELECT group_concat(name) FROM pragma_table_info('$table');")
    for column in ${columns//,/ }; do
      case ",$present," in
        *",$column,"*) ;;
        *) scenario_fail "the fixture schema lacks $table.$column" || return 1 ;;
      esac
    done
  done < <(sed -n "/^RUNTIME_STORE_SCHEMA='/,/'$/p" \
    "$REPOSITORY_ROOT/opencode/_runtime-store.sh" \
    | sed "s/^RUNTIME_STORE_SCHEMA='//; s/'$//" | grep -v '^$')
}

# Faults at the operating-system boundary, for what the real tools cannot be
# made to do on demand: a removal that fails or claims success, a measurement
# that fails or is incomplete, a Git step that fails, and a directory replaced
# between the doctor's decision and its action.
#
# Each wrapper has the fixture's root written into it and acts only on paths
# below that root. Every other call, and every call no fault names, reaches the
# real tool, so nothing outside the fixture can be touched. Faults arrive per
# run through fixture_run, one table_row per path. They are tables keyed by
# path, not the stubs' single exit status or output, so they carry their own
# FAULT_<COMMAND> prefix rather than bending FAIL_ and FAKE_ to mean something
# else.
#
#   FAULT_RM            <path> persistent | partial | claimed | read-only
#   FAULT_CHMOD         <path>
#   FAULT_DU            <path> failed | incomplete | malformed | first
#   FAULT_DU_KILOBYTES  <path> <kilobytes of its own contents>
#   FAULT_GIT           <path> <another argument of the same call>
#   FAULT_GIT_REPLACE   <path> <another argument> gone | file | symlink | dangling
#   FAULT_RMDIR         <path>
#   FAULT_SQLITE3       <database written to>
#
# Every call a wrapper sees on a fixture path goes to the event log in the
# stubs' shape, so a scenario can count what the doctor attempted.
install_fault_wrappers() {
  local fixture=$1 command

  for command in rm chmod du git rmdir sqlite3; do
    {
      printf '#!/bin/sh\nfixture_root=%s\n' "'$fixture'"
      fault_wrapper_prelude
      "fault_wrapper_$command"
    } | scenario_write_executable "$fixture/fake-bin/$command"
  done
}

fault_wrapper_prelude() {
  cat <<'EOF'
tab=$(printf '\t')

inside_fixture() {
  case $1 in
    "$fixture_root"/*) return 0 ;;
  esac
  return 1
}

record() {
  [ -z "${SCENARIO_EVENT_LOG:-}" ] || printf '%s\n' "$*" >>"$SCENARIO_EVENT_LOG"
}

# What follows <path> in the first row of <table> that names it, or "fail" for
# a row naming nothing else.
fault_for() {
  inside_fixture "$2" || return 0
  printf '%s\n' "$1" | while IFS=$tab read -r fault_path fault_rest; do
    if [ "$fault_path" = "$2" ]; then
      printf '%s\n' "${fault_rest:-fail}"
      break
    fi
  done
}

has_argument() {
  wanted=$1
  shift
  for argument in "$@"; do
    [ "$argument" != "$wanted" ] || return 0
  done
  return 1
}

for target in "$@"; do :; done
EOF
}

fault_wrapper_rm() {
  cat <<'EOF'
inside_fixture "$target" && record "rm $*"
case $(fault_for "${FAULT_RM:-}" "$target") in
  persistent) exit 1 ;;
  claimed) exit 0 ;;
  partial)
    # What identifies the directory goes -- the files directly inside it and
    # any .git -- and the rest stays standing.
    if [ -d "$target" ] && [ ! -L "$target" ]; then
      /usr/bin/find "$target" -mindepth 1 -maxdepth 1 \( ! -type d -o -name .git \) \
        -exec /bin/rm -rf -- {} +
    fi
    exit 1
    ;;
  read-only)
    # What the kernel does for an unprivileged user, whoever runs the suite.
    [ -z "$(/usr/bin/find "$target" -type d ! -perm -200 -print 2>/dev/null)" ] || exit 1
    ;;
esac
exec /bin/rm "$@"
EOF
}

fault_wrapper_chmod() {
  cat <<'EOF'
inside_fixture "$target" && record "chmod $*"
[ -z "$(fault_for "${FAULT_CHMOD:-}" "$target")" ] || exit 1
exec /bin/chmod "$@"
EOF
}

fault_wrapper_du() {
  cat <<'EOF'
inside_fixture "$target" || exec /usr/bin/du "$@"

fault=$(fault_for "${FAULT_DU:-}" "$target")
if [ "$fault" = first ]; then
  fault=failed
  if grep -Fqx -- "du $*" "$SCENARIO_EVENT_LOG" 2>/dev/null; then
    fault=''
  fi
fi
record "du $*"
case $fault in
  failed)
    printf 'du: %s: Permission denied\n' "$target" >&2
    exit 1
    ;;
  malformed)
    printf 'unknown%s%s\n' "$tab" "$target"
    exit 0
    ;;
esac

# A declared size is a path's own contents, so a directory measures as the sum
# of the declared paths still inside it.
kilobytes=''
while IFS=$tab read -r sized_path sized_kilobytes; do
  case $sized_path in
    "$target" | "$target"/*)
      [ -e "$sized_path" ] || continue
      kilobytes=$((${kilobytes:-0} + sized_kilobytes))
      ;;
  esac
done <<ROWS
${FAULT_DU_KILOBYTES:-}
ROWS

status=0
if [ -n "$kilobytes" ]; then
  printf '%s%s%s\n' "$kilobytes" "$tab" "$target"
else
  /usr/bin/du "$@" || status=$?
fi
if [ "$fault" = incomplete ]; then
  printf 'du: %s: Permission denied\n' "$target/unreadable" >&2
  exit 1
fi
exit "$status"
EOF
}

fault_wrapper_git() {
  cat <<'EOF'
# The first row of <table> whose path and word are both arguments of this
# call, printed as its path and the rest of the row.
matching_row() {
  table=$1
  shift
  printf '%s\n' "$table" | while IFS=$tab read -r row_path row_word row_rest; do
    inside_fixture "$row_path" || continue
    has_argument "$row_path" "$@" || continue
    has_argument "$row_word" "$@" || continue
    printf '%s%s%s\n' "$row_path" "$tab" "$row_rest"
    break
  done
}

if [ -n "$(matching_row "${FAULT_GIT:-}" "$@")" ]; then
  record "git $*"
  printf 'fatal: injected failure\n' >&2
  exit 128
fi

replacement=$(matching_row "${FAULT_GIT_REPLACE:-}" "$@")
[ -n "$replacement" ] || exec /usr/bin/git "$@"

# The call is answered, and then the path changes underneath the doctor, once,
# the way something else running on the machine would change it.
status=0
/usr/bin/git "$@" || status=$?
replaced=${replacement%%"$tab"*}
if ! grep -Fqx -- "replaced $replaced" "$SCENARIO_EVENT_LOG" 2>/dev/null; then
  record "replaced $replaced"
  /bin/rm -rf -- "$replaced"
  case ${replacement#*"$tab"} in
    file) printf 'not a directory\n' >"$replaced" ;;
    symlink) /bin/ln -s "$fixture_root/outside" "$replaced" ;;
    dangling) /bin/ln -s "$fixture_root/nowhere" "$replaced" ;;
  esac
fi
exit "$status"
EOF
}

fault_wrapper_rmdir() {
  cat <<'EOF'
inside_fixture "$target" && record "rmdir $*"
if [ -n "$(fault_for "${FAULT_RMDIR:-}" "$target")" ]; then
  printf 'rmdir: %s: Operation not permitted\n' "$target" >&2
  exit 1
fi
exec /bin/rmdir "$@"
EOF
}

fault_wrapper_sqlite3() {
  cat <<'EOF'
# A read opens the database through a read-only URI; a write names the file.
if [ -n "$(fault_for "${FAULT_SQLITE3:-}" "${1:-}")" ]; then
  printf 'Error: injected write failure\n' >&2
  exit 1
fi
exec /usr/bin/sqlite3 "$@"
EOF
}

# One row of a fault or size table: its fields joined by tabs.
table_row() {
  local IFS=$'\t'
  printf '%s\n' "$*"
}

# How many times a wrapper saw <command> run with <path> as its last argument.
calls_on() {
  local log=$1 command=$2 path=$3
  awk -v command="$command " -v suffix=" $path" '
    index($0, command) == 1 && length($0) >= length(suffix) \
      && substr($0, length($0) - length(suffix) + 1) == suffix { count++ }
    END { print count + 0 }
  ' "$log"
}

# A read-only directory the doctor failed to retire would otherwise outlive
# the suite's own cleanup. The trap belongs to the scenario's subshell.
restore_write_permission_on_exit() {
  # shellcheck disable=SC2064 # The fixture path is fixed when the trap is set.
  trap "chmod -R u+w '$1' 2>/dev/null || :" EXIT
}

# The three directories a repair retires by default, one per condition.
set_retirement_targets() {
  snapshot=$1/data/snapshot/project/lost
  artifact=$1/data/worktree/project/live-worktree/.opencode-artifacts/idle
  checkout=$1/data/worktree/project/pushed
}

test_each_condition_confirms_a_complete_retirement() {
  local fixture snapshot artifact checkout
  fixture=$(make_fixture)
  make_worktree_checkouts "$fixture"
  install_fault_wrappers "$fixture"
  set_retirement_targets "$fixture"

  invoke_doctor "$fixture" --artifacts "$fixture/report"
  assert_equal 0 "$(grep -Ec '^(rm|chmod|rmdir) ' "$fixture/report/events.log" || true)" \
    'removals attempted by a report'

  invoke_doctor "$fixture" --fix
  [ ! -e "$snapshot" ] || scenario_fail 'a lost snapshot survived'
  [ ! -e "$artifact" ] || scenario_fail 'an idle artifact directory survived'
  [ ! -e "$checkout" ] || scenario_fail 'a reconstructible checkout survived'
  assert_contains "$fixture/stdout.log" 'removed 1 session snapshot(s) describing a missing directory'
  assert_contains "$fixture/stdout.log" 'retired 1 delegation artifact directory(ies)'
  assert_contains "$fixture/stdout.log" 'retired 2 agent worktree checkout(s)'
  assert_contains "$fixture/stdout.log" 'OpenCode state repaired'
  assert_not_contains "$fixture/stderr.log" 'could not retire'
}

# A read-only subtree survives the first removal. One permission repair and one
# more attempt retire it, in every condition that retires directories.
test_each_condition_recovers_with_one_permission_repair() {
  local fixture snapshot artifact checkout target
  fixture=$(make_fixture)
  make_worktree_checkouts "$fixture"
  install_fault_wrappers "$fixture"
  restore_write_permission_on_exit "$fixture"
  set_retirement_targets "$fixture"

  for target in "$snapshot" "$artifact" "$checkout/.git"; do
    mkdir -p "$target/cache/locked"
    printf 'signed\n' >"$target/cache/locked/bundle"
    chmod a-w "$target/cache/locked"
  done
  backdate "$artifact"

  invoke_doctor "$fixture" \
    FAULT_RM="$(
      table_row "$snapshot" read-only
      table_row "$artifact" read-only
      table_row "$checkout" read-only
    )" \
    --fix

  for target in "$snapshot" "$artifact" "$checkout"; do
    [ ! -e "$target" ] || scenario_fail "a read-only subtree kept $target"
    assert_equal 2 "$(calls_on "$fixture/events.log" rm "$target")" "removals of $target"
    assert_equal 1 "$(calls_on "$fixture/events.log" chmod "$target")" "permission repairs of $target"
  done
  assert_contains "$fixture/stdout.log" 'OpenCode state repaired'
  assert_not_contains "$fixture/stderr.log" 'could not retire'
}

# When the permission repair itself fails, the second attempt meets the same
# read-only subtree. The directory is kept, and the diagnostic names the step
# that failed rather than only the removal that followed it.
test_a_failed_permission_repair_keeps_the_directory_and_says_so() {
  local fixture snapshot artifact checkout
  fixture=$(make_fixture)
  make_worktree_checkouts "$fixture"
  install_fault_wrappers "$fixture"
  restore_write_permission_on_exit "$fixture"
  set_retirement_targets "$fixture"

  mkdir -p "$artifact/cache/locked"
  printf 'signed\n' >"$artifact/cache/locked/bundle"
  chmod a-w "$artifact/cache/locked"
  backdate "$artifact"

  assert_fails_with_status 1 invoke_doctor "$fixture" \
    FAULT_RM="$(table_row "$artifact" read-only)" \
    FAULT_CHMOD="$(table_row "$artifact")" \
    --fix

  [ -f "$artifact/cache/locked/bundle" ] || scenario_fail 'the read-only subtree was removed'
  assert_equal 2 "$(calls_on "$fixture/events.log" rm "$artifact")" "removals of $artifact"
  assert_equal 1 "$(calls_on "$fixture/events.log" chmod "$artifact")" "permission repairs of $artifact"
  assert_contains "$fixture/stderr.log" \
    "could not retire $artifact: it survived removal, and its write permission could not be restored"
  assert_not_contains "$fixture/stdout.log" 'retired 1 delegation artifact directory(ies)'
  [ ! -e "$snapshot" ] || scenario_fail 'the independent snapshot was not retired'
}

# A removal that keeps failing is attempted twice around one permission repair,
# named, and counted against the run, while every repair that does not depend
# on it -- another checkout, a later condition -- still happens.
test_each_condition_fails_a_persistent_removal_and_continues() {
  local fixture snapshot artifact checkout target
  fixture=$(make_fixture)
  make_worktree_checkouts "$fixture"
  install_fault_wrappers "$fixture"
  set_retirement_targets "$fixture"
  printf 'a log line\n' >"$fixture/data/log/opencode.log"

  assert_fails_with_status 1 invoke_doctor "$fixture" \
    FAULT_RM="$(
      table_row "$snapshot" persistent
      table_row "$artifact" persistent
      table_row "$checkout" persistent
    )" \
    --fix --clear-logs

  for target in "$snapshot" "$artifact" "$checkout"; do
    [ -d "$target" ] || scenario_fail "a failed removal lost $target"
    assert_contains "$fixture/stderr.log" "could not retire $target: it survived removal"
    assert_equal 2 "$(calls_on "$fixture/events.log" rm "$target")" "removals of $target"
    assert_equal 1 "$(calls_on "$fixture/events.log" chmod "$target")" "permission repairs of $target"
  done
  [ ! -e "$fixture/data/worktree/project/spaced name" ] \
    || scenario_fail 'an independent checkout was not retired'
  [ ! -e "$fixture/data/log/opencode.log" ] || scenario_fail 'a later condition did not run'
  assert_not_contains "$fixture/stdout.log" 'removed 1 session snapshot(s)'
  assert_not_contains "$fixture/stdout.log" 'delegation artifact directory(ies),'
  assert_contains "$fixture/stdout.log" 'retired 1 agent worktree checkout(s)'
  assert_not_contains "$fixture/stdout.log" 'OpenCode state repaired'
  assert_contains "$fixture/stderr.log" \
    'OpenCode repair incomplete: 3 directory(ies) not retired, 0 Git registration(s) left behind'
}

# Part of a directory is gone and the rest is not. Nothing about it is counted,
# not even the bytes that did go, and the directories beside it still are.
test_a_partial_removal_counts_neither_directory_nor_bytes() {
  local fixture artifact_root root name
  fixture=$(make_fixture)
  make_worktree_checkouts "$fixture"
  install_fault_wrappers "$fixture"
  root=$fixture/data/worktree/project
  artifact_root=$root/live-worktree/.opencode-artifacts
  for name in partial other; do
    mkdir -p "$artifact_root/$name/trace"
    printf 'evidence\n' >"$artifact_root/$name/screenshot.png"
    printf 'evidence\n' >"$artifact_root/$name/trace/steps.log"
    backdate "$artifact_root/$name"
  done

  assert_fails_with_status 1 invoke_doctor "$fixture" LC_ALL=C \
    FAULT_DU_KILOBYTES="$(
      table_row "$artifact_root/idle" 16
      table_row "$artifact_root/partial" 32
      table_row "$artifact_root/other" 64
    )" \
    FAULT_RM="$(table_row "$artifact_root/partial" partial)" \
    --fix

  [ ! -e "$artifact_root/idle" ] || scenario_fail 'an idle artifact directory survived'
  [ ! -e "$artifact_root/other" ] || scenario_fail 'an independent artifact directory survived'
  [ ! -e "$artifact_root/partial/screenshot.png" ] || scenario_fail 'the fault removed nothing'
  [ -e "$artifact_root/partial/trace/steps.log" ] || scenario_fail 'the fault removed everything'
  assert_contains "$fixture/stdout.log" 'retired 2 delegation artifact directory(ies), 80.0 KB'
  assert_contains "$fixture/stderr.log" "could not retire $artifact_root/partial: it survived removal"
  [ ! -e "$root/pushed" ] || scenario_fail 'a later condition stopped at the failure'
  assert_contains "$fixture/stdout.log" 'retired 2 agent worktree checkout(s)'
  assert_contains "$fixture/stderr.log" 'OpenCode repair incomplete: 1 directory(ies) not retired'
  assert_not_contains "$fixture/stdout.log" 'OpenCode state repaired'
}

# An exit status is not proof: a removal that reports success while the
# directory is still there has retired nothing.
test_a_removal_that_claims_success_is_not_a_retirement() {
  local fixture snapshot artifact checkout
  fixture=$(make_fixture)
  install_fault_wrappers "$fixture"
  set_retirement_targets "$fixture"

  assert_fails_with_status 1 invoke_doctor "$fixture" \
    FAULT_RM="$(
      table_row "$snapshot" claimed
      table_row "$artifact" claimed
    )" \
    --fix

  [ -d "$snapshot" ] || scenario_fail 'the claimed snapshot removal was real'
  [ -d "$artifact" ] || scenario_fail 'the claimed artifact removal was real'
  assert_contains "$fixture/stderr.log" "could not retire $snapshot: it survived removal"
  assert_contains "$fixture/stderr.log" "could not retire $artifact: it survived removal"
  assert_not_contains "$fixture/stdout.log" 'removed 1 session snapshot(s)'
  assert_not_contains "$fixture/stdout.log" 'retired 1 delegation artifact directory(ies)'
  assert_contains "$fixture/stderr.log" 'OpenCode repair incomplete: 2 directory(ies) not retired'
}

# An unknown size is not zero, and a directory whose measurement failed once is
# not retired on the strength of a later one that succeeds: "first" fails only
# the report's measurement of an artifact and a checkout.
test_an_unmeasured_directory_is_kept_for_the_whole_run() {
  local mode fixture snapshot artifact checkout target
  for mode in failed incomplete malformed first; do
    fixture=$(make_fixture)
    make_worktree_checkouts "$fixture"
    install_fault_wrappers "$fixture"
    set_retirement_targets "$fixture"

    assert_fails_with_status 1 invoke_doctor "$fixture" \
      FAULT_DU="$(
        table_row "$snapshot" "$mode"
        table_row "$artifact" "$mode"
        table_row "$checkout" "$mode"
      )" \
      --fix

    [ -f "$snapshot/config" ] || scenario_fail "$mode measurement: the snapshot lost content"
    [ -f "$artifact/screenshot.png" ] || scenario_fail "$mode measurement: the artifact lost content"
    [ -f "$checkout/file.txt" ] || scenario_fail "$mode measurement: the checkout lost content"
    for target in "$snapshot" "$artifact" "$checkout"; do
      assert_equal 0 "$(calls_on "$fixture/events.log" rm "$target")" \
        "$mode measurement: removals of $target"
      assert_contains "$fixture/stderr.log" \
        "could not retire $target: its size could not be measured"
    done
    assert_contains "$fixture/stderr.log" "could not measure $artifact"
    assert_contains "$fixture/stderr.log" "could not measure $checkout"
    [ ! -e "$fixture/data/worktree/project/spaced name" ] \
      || scenario_fail "$mode measurement: an independent checkout was not retired"
    assert_contains "$fixture/stderr.log" 'OpenCode repair incomplete: 3 directory(ies) not retired'
  done
}

# Something else removed the directory after the doctor chose it. That is
# neither a retirement nor a failure, and a linked checkout gone before its
# owner could be asked is not mistaken for one whose owner is unknown -- nor
# does it clear a failure the run already holds.
test_a_directory_gone_before_action_is_neither_counted_nor_failed() {
  local fixture snapshot artifact checkout
  fixture=$(make_fixture)
  make_linked_worktrees "$fixture" agent
  install_fault_wrappers "$fixture"
  set_retirement_targets "$fixture"
  checkout=$fixture/data/worktree/project/agent

  invoke_doctor "$fixture" \
    FAULT_GIT_REPLACE="$(
      table_row "$snapshot" config gone
      table_row "$checkout" log gone
    )" \
    --fix

  [ ! -e "$snapshot" ] || scenario_fail 'the snapshot never vanished'
  [ ! -e "$checkout" ] || scenario_fail 'the checkout never vanished'
  assert_equal 0 "$(calls_on "$fixture/events.log" rm "$snapshot")" 'removals of a vanished snapshot'
  assert_equal 0 "$(calls_on "$fixture/events.log" rm "$checkout")" 'removals of a vanished checkout'
  assert_not_contains "$fixture/stdout.log" 'removed 1 session snapshot(s)'
  assert_not_contains "$fixture/stdout.log" 'retired 1 agent worktree checkout(s)'
  assert_not_contains "$fixture/stderr.log" 'could not retire'
  assert_contains "$fixture/stdout.log" 'OpenCode state repaired'

  fixture=$(make_fixture)
  make_linked_worktrees "$fixture" agent
  install_fault_wrappers "$fixture"
  set_retirement_targets "$fixture"
  checkout=$fixture/data/worktree/project/agent

  assert_fails_with_status 1 invoke_doctor "$fixture" \
    FAULT_RM="$(table_row "$artifact" persistent)" \
    FAULT_GIT_REPLACE="$(table_row "$checkout" log gone)" \
    --fix

  assert_not_contains "$fixture/stderr.log" "could not retire $checkout"
  assert_contains "$fixture/stderr.log" 'OpenCode repair incomplete: 1 directory(ies) not retired'
}

# Deciding that a directory may go does not authorize removing whatever took
# its place: a file, a link to somewhere else, or a link to nothing.
test_a_directory_replaced_before_action_is_kept() {
  local kind fixture snapshot artifact checkout target
  for kind in file symlink dangling; do
    fixture=$(make_fixture)
    make_linked_worktrees "$fixture" agent
    install_fault_wrappers "$fixture"
    set_retirement_targets "$fixture"
    checkout=$fixture/data/worktree/project/agent
    mkdir "$fixture/outside"
    printf 'keep\n' >"$fixture/outside/keep.txt"

    # A zero-day window, because the replacement is new and would otherwise
    # keep the checkout inside the retention window before retirement is asked.
    assert_fails_with_status 1 invoke_doctor "$fixture" \
      FAULT_GIT_REPLACE="$(
        table_row "$snapshot" config "$kind"
        table_row "$checkout" log "$kind"
      )" \
      --fix --days 0

    for target in "$snapshot" "$checkout"; do
      if [ "$kind" = file ]; then
        [ -f "$target" ] || scenario_fail "a replacing file was removed: $target"
      else
        [ -L "$target" ] || scenario_fail "a replacing $kind was removed: $target"
      fi
      assert_contains "$fixture/stderr.log" "could not retire $target: it is no longer a directory"
      assert_equal 0 "$(calls_on "$fixture/events.log" rm "$target")" "removals of a replaced $target"
      assert_equal 0 "$(calls_on "$fixture/events.log" chmod "$target")" "permission changes on a replaced $target"
    done
    assert_contains "$fixture/outside/keep.txt" 'keep'
    assert_contains "$fixture/stderr.log" 'OpenCode repair incomplete: 2 directory(ies) not retired'
  done
}

# A zero-day window skips the age check and nothing else: a checkout holding an
# artifact the run could not retire, or refused to, is kept. The rule follows
# ancestry rather than spelling, so a failure inside pushed-copy says nothing
# about pushed.
test_a_failed_artifact_keeps_its_checkout_under_zero_retention() {
  local fixture root
  fixture=$(make_fixture)
  make_worktree_checkouts "$fixture"
  make_pushed_checkout "$fixture" pushed-copy
  root=$fixture/data/worktree/project
  make_artifact "$root/pushed-copy" run
  make_artifact "$root/spaced name" run
  install_fault_wrappers "$fixture"

  assert_fails_with_status 1 invoke_doctor "$fixture" \
    FAULT_RM="$(table_row "$root/pushed-copy/.opencode-artifacts/run" persistent)" \
    FAULT_DU="$(table_row "$root/spaced name/.opencode-artifacts/run" failed)" \
    --fix --days 0

  [ -d "$root/pushed-copy/.opencode-artifacts/run" ] || scenario_fail 'a failed artifact was removed with its checkout'
  [ -d "$root/spaced name/.opencode-artifacts/run" ] || scenario_fail 'a refused artifact was removed with its checkout'
  assert_contains "$fixture/stderr.log" \
    "could not retire $root/pushed-copy: $root/pushed-copy/.opencode-artifacts/run inside it was not retired"
  assert_contains "$fixture/stderr.log" \
    "could not retire $root/spaced name: $root/spaced name/.opencode-artifacts/run inside it was not retired"
  [ ! -e "$root/pushed" ] || scenario_fail 'a checkout sharing only a name prefix with a failure was kept'
  [ ! -e "$root/live-worktree/.opencode-artifacts/fresh" ] || scenario_fail 'an unrelated artifact was kept'
  assert_contains "$fixture/stdout.log" 'retired 1 agent worktree checkout(s)'
  assert_contains "$fixture/stderr.log" 'OpenCode repair incomplete: 4 directory(ies) not retired'
}

# Retired bytes are pre-removal sizes, measured when each directory goes, so an
# artifact retired first is not counted again inside its checkout.
test_an_artifact_retired_before_its_checkout_is_counted_once() {
  local fixture root artifact_root
  fixture=$(make_fixture)
  make_worktree_checkouts "$fixture"
  root=$fixture/data/worktree/project
  artifact_root=$root/live-worktree/.opencode-artifacts
  make_artifact "$root/pushed" run
  install_fault_wrappers "$fixture"

  invoke_doctor "$fixture" LC_ALL=C \
    FAULT_DU_KILOBYTES="$(
      table_row "$artifact_root/fresh" 4
      table_row "$artifact_root/idle" 4
      table_row "$artifact_root/bulky" 8
      table_row "$root/pushed/.opencode-artifacts/run" 64
      table_row "$root/pushed" 16
      table_row "$root/spaced name" 8
    )" \
    --fix --days 0

  assert_contains "$fixture/stdout.log" 'retired 4 delegation artifact directory(ies), 80.0 KB'
  assert_contains "$fixture/stdout.log" 'retired 2 agent worktree checkout(s), 24.0 KB'
}

# A linked worktree's registration lives in its owner. Retiring the checkout
# removes that registration and no other: not a live sibling's, and not one
# whose directory is merely unreachable, the way a worktree on an unmounted
# volume is.
test_a_retired_linked_worktree_leaves_no_registration() {
  local fixture owner
  fixture=$(make_fixture)
  make_linked_worktrees "$fixture" agent
  owner=$fixture/owner/.git
  git -C "$fixture/owner" worktree add --quiet --track -b unmounted \
    "$fixture/unmounted" origin/main
  mv "$fixture/unmounted" "$fixture/unmounted.away"

  invoke_doctor "$fixture" --fix

  [ ! -e "$fixture/data/worktree/project/agent" ] || scenario_fail 'the linked checkout survived'
  [ ! -e "$owner/worktrees/agent" ] || scenario_fail 'its registration survived'
  [ -f "$fixture/sibling/file.txt" ] || scenario_fail 'a sibling worktree was touched'
  [ -d "$owner/worktrees/sibling" ] || scenario_fail "a sibling's registration was removed"
  [ -d "$owner/worktrees/unmounted" ] || scenario_fail 'an unreachable registration was discarded'
  assert_contains "$fixture/stdout.log" 'retired 1 agent worktree checkout(s)'
  assert_contains "$fixture/stdout.log" 'OpenCode state repaired'
}

test_an_unidentified_owner_keeps_the_linked_checkout() {
  local fixture checkout
  fixture=$(make_fixture)
  make_linked_worktrees "$fixture" agent
  install_fault_wrappers "$fixture"
  checkout=$fixture/data/worktree/project/agent

  assert_fails_with_status 1 invoke_doctor "$fixture" \
    FAULT_GIT="$(table_row "$checkout" --git-common-dir)" \
    --fix

  [ -f "$checkout/file.txt" ] || scenario_fail 'the checkout lost its content'
  [ -f "$checkout/.git" ] || scenario_fail 'the checkout lost what names its owner'
  [ -d "$fixture/owner/.git/worktrees/agent" ] || scenario_fail 'its registration was touched'
  assert_equal 0 "$(calls_on "$fixture/events.log" rm "$checkout")" 'removals of an unidentified checkout'
  assert_contains "$fixture/stderr.log" "could not retire $checkout: its Git owner could not be identified"
  assert_contains "$fixture/stderr.log" 'Nothing was removed.'
  assert_contains "$fixture/stderr.log" 'OpenCode repair incomplete: 1 directory(ies) not retired'
}

# The checkout is gone and stays counted; the registration its owner still
# holds is a failure of its own, named with that owner while the run knows it.
test_a_failed_registration_cleanup_keeps_the_retirement_and_fails() {
  local fixture root owner
  fixture=$(make_fixture)
  make_worktree_checkouts "$fixture"
  make_linked_worktrees "$fixture" agent
  install_fault_wrappers "$fixture"
  root=$fixture/data/worktree/project
  owner=$fixture/owner/.git
  printf 'a log line\n' >"$fixture/data/log/opencode.log"

  assert_fails_with_status 1 invoke_doctor "$fixture" LC_ALL=C \
    FAULT_GIT="$(table_row "$owner" worktree)" \
    FAULT_DU_KILOBYTES="$(
      table_row "$root/agent" 32
      table_row "$root/pushed" 16
      table_row "$root/spaced name" 8
    )" \
    --fix --clear-logs

  [ ! -e "$root/agent" ] || scenario_fail 'the linked checkout survived'
  [ -d "$owner/worktrees/agent" ] || scenario_fail 'the fault did not keep the registration'
  assert_contains "$fixture/stdout.log" 'retired 3 agent worktree checkout(s), 56.0 KB'
  assert_contains "$fixture/stderr.log" \
    "retired $root/agent, but could not remove its Git registration from $owner"
  [ ! -e "$root/pushed" ] || scenario_fail 'an independent checkout was not retired'
  [ ! -e "$fixture/data/log/opencode.log" ] || scenario_fail 'a later condition did not run'
  assert_contains "$fixture/stderr.log" \
    'OpenCode repair incomplete: 0 directory(ies) not retired, 1 Git registration(s) left behind'
  assert_not_contains "$fixture/stdout.log" 'OpenCode state repaired'
}

# The owner is known only while the checkout that names it exists, so the run
# that fails says so and says how to finish by hand; a later run has nothing to
# rediscover it from and does not pretend otherwise.
test_a_registration_left_behind_is_named_only_by_the_run_that_knew_it() {
  local fixture owner
  fixture=$(make_fixture)
  make_linked_worktrees "$fixture" agent
  install_fault_wrappers "$fixture"
  owner=$fixture/owner/.git

  assert_fails_with_status 1 invoke_doctor "$fixture" \
    FAULT_GIT="$(table_row "$owner" worktree)" \
    --fix
  assert_contains "$fixture/stderr.log" "git --git-dir '$owner' worktree list"
  assert_contains "$fixture/stderr.log" 'a later run cannot find this owner'
  assert_not_contains "$fixture/stderr.log" 'rerun'

  invoke_doctor "$fixture" --artifacts "$fixture/second" --fix --days 0
  assert_not_contains "$fixture/second/stdout.log" "$owner"
  assert_not_contains "$fixture/second/stderr.log" "$owner"
  [ -d "$owner/worktrees/agent" ] || scenario_fail 'a later run rediscovered the owner'
}

test_a_retired_clone_owes_no_registration_cleanup() {
  local fixture root
  fixture=$(make_fixture)
  make_worktree_checkouts "$fixture"
  install_fault_wrappers "$fixture"
  root=$fixture/data/worktree/project

  invoke_doctor "$fixture" --fix

  [ ! -e "$root/pushed" ] || scenario_fail 'a pushed clone survived'
  assert_not_contains "$fixture/stderr.log" 'registration'
  assert_not_contains "$fixture/stderr.log" 'could not retire'
  assert_contains "$fixture/stdout.log" 'OpenCode state repaired'
}

# Removing the hash directory above a retired snapshot is tidying. When it is
# kept -- because other snapshots live there, or because it cannot be removed
# -- the retirement stands and the siblings are untouched.
test_a_kept_snapshot_parent_does_not_undo_the_retirement() {
  local fixture snapshots
  fixture=$(make_fixture)
  make_lost_snapshot "$fixture" alone
  install_fault_wrappers "$fixture"
  snapshots=$fixture/data/snapshot

  invoke_doctor "$fixture" FAULT_RMDIR="$(table_row "$snapshots/alone")" --fix

  [ ! -e "$snapshots/project/lost" ] || scenario_fail 'a lost snapshot survived'
  [ ! -e "$snapshots/alone/lost" ] || scenario_fail 'a lost snapshot alone in its parent survived'
  [ -d "$snapshots/alone" ] || scenario_fail 'the fault did not keep the empty parent'
  assert_equal "$fixture/data/worktree/project/live-worktree" \
    "$(git --git-dir "$snapshots/project/live" config --get core.worktree 2>/dev/null)" \
    'a sibling snapshot beside a retired one'
  [ -d "$snapshots/project/unset" ] || scenario_fail 'an unjudgeable sibling was removed'
  assert_contains "$fixture/stdout.log" 'removed 2 session snapshot(s) describing a missing directory'
  assert_contains "$fixture/stdout.log" 'OpenCode state repaired'

  fixture=$(make_fixture)
  make_lost_snapshot "$fixture" alone
  invoke_doctor "$fixture" --fix
  [ ! -e "$fixture/data/snapshot/alone" ] || scenario_fail 'an empty parent was kept without cause'
}

# A partial removal can take what identified the directory. The next run
# judges it afresh, finds nothing it can judge, and keeps it even with a zero-day
# window; the run that failed is the one that says recovery is manual.
test_a_partial_removal_is_not_resumed_by_a_later_run() {
  local fixture snapshot artifact checkout owner
  fixture=$(make_fixture)
  make_linked_worktrees "$fixture" agent
  install_fault_wrappers "$fixture"
  set_retirement_targets "$fixture"
  checkout=$fixture/data/worktree/project/agent
  owner=$fixture/owner/.git

  assert_fails_with_status 1 invoke_doctor "$fixture" \
    FAULT_RM="$(
      table_row "$snapshot" partial
      table_row "$checkout" partial
    )" \
    --fix

  [ -d "$snapshot" ] || scenario_fail 'a partly removed snapshot was reported gone'
  [ ! -e "$snapshot/config" ] || scenario_fail 'the snapshot fault did not apply'
  [ -d "$checkout" ] || scenario_fail 'a partly removed checkout was reported gone'
  [ ! -e "$checkout/.git" ] || scenario_fail 'the checkout fault did not apply'
  assert_contains "$fixture/stderr.log" "could not retire $snapshot: it survived removal"
  assert_contains "$fixture/stderr.log" "could not retire $checkout: it survived removal"
  assert_contains "$fixture/stderr.log" "Its Git owner is $owner."
  assert_contains "$fixture/stderr.log" 'Inspect and recover it by hand.'
  assert_not_contains "$fixture/stderr.log" 'rerun'

  invoke_doctor "$fixture" --artifacts "$fixture/second" --fix --days 0

  [ -d "$snapshot" ] || scenario_fail 'an unidentifiable snapshot was removed'
  [ -d "$checkout" ] || scenario_fail 'an unidentifiable checkout was removed'
  assert_contains "$fixture/second/stdout.log" 'checkouts nothing here can judge, and so keeps: 2'
  assert_not_contains "$fixture/second/stdout.log" 'removed 1 session snapshot(s)'
  assert_not_contains "$fixture/second/stdout.log" 'agent worktree checkout(s),'
  assert_not_contains "$fixture/second/stderr.log" 'could not retire'
}

# Carrying on past a failure is the directory repairs' rule and nobody else's:
# a write the runtime store cannot make still stops the run where it happens.
test_a_fatal_condition_still_stops_the_run() {
  local fixture snapshot artifact checkout
  fixture=$(make_fixture)
  install_fault_wrappers "$fixture"
  set_retirement_targets "$fixture"

  assert_fails_with_status 1 invoke_doctor "$fixture" \
    FAULT_SQLITE3="$(table_row "$fixture/data/opencode.db")" \
    --fix

  [ -d "$snapshot" ] || scenario_fail 'a condition after the fatal one ran'
  [ -d "$artifact" ] || scenario_fail 'a condition after the fatal one ran'
  assert_not_contains "$fixture/stdout.log" 'session snapshots'
  assert_not_contains "$fixture/stdout.log" 'OpenCode state repaired'
  assert_not_contains "$fixture/stderr.log" 'OpenCode repair incomplete'
}

scenario_run 'a report names state without changing it' test_report_names_state_without_changing_it
scenario_run 'an untracked shadowing config is reported' test_untracked_shadowing_config_is_reported
scenario_run 'a clean config directory reports nothing' test_clean_config_directory_is_not_reported
scenario_run 'a repair prunes finished and stale sessions only' test_fix_prunes_finished_and_stale_sessions_only
scenario_run 'the retention window protects only unfinished sessions' test_retention_window_is_selectable
scenario_run 'a report names sessions whose workspace is gone' test_report_names_sessions_whose_workspace_is_gone
scenario_run 'a repair releases only sessions whose workspace is gone' test_fix_releases_only_sessions_whose_workspace_is_gone
scenario_run 'a report names snapshots whose directory is gone' test_report_names_snapshots_whose_directory_is_gone
scenario_run 'a repair removes only snapshots whose directory is gone' test_fix_removes_only_snapshots_whose_directory_is_gone
# The checkout itself had no owner before this condition: every other one
# reaches inside a worktree -- the processes, the snapshots, the artifacts --
# and none of them removed the directory holding them, so a retired session's
# node_modules stayed forever. A report still changes nothing.
test_report_names_worktree_checkouts_without_retiring_them() {
  local fixture root
  fixture=$(make_fixture)
  make_worktree_checkouts "$fixture"
  root=$fixture/data/worktree/project
  invoke_doctor "$fixture"

  assert_contains "$fixture/stdout.log" 'agent worktree checkouts: 5'
  assert_contains "$fixture/stdout.log" 'retired checkouts (idle for 7 days): 2'
  # live-worktree is not a Git checkout, so nothing here can judge it.
  assert_contains "$fixture/stdout.log" 'checkouts nothing here can judge, and so keeps: 1'
  assert_contains "$fixture/stderr.log" "worktree holds work that is not on a remote: $root/unpushed"
  assert_contains "$fixture/stderr.log" "worktree holds work that is not on a remote: $root/dirty"
  [ -d "$root/pushed" ] || scenario_fail 'a report must not retire anything'
}

# Only the checkout whose every byte exists on the origin goes. An unpushed
# commit and an uncommitted change are both work that exists nowhere else, and
# a retention window has no standing to discard either.
test_fix_retires_only_reconstructible_worktree_checkouts() {
  local fixture root
  fixture=$(make_fixture)
  make_worktree_checkouts "$fixture"
  root=$fixture/data/worktree/project
  invoke_doctor "$fixture" --fix

  [ ! -d "$root/pushed" ] || scenario_fail 'a fully pushed checkout must be retired'
  [ -d "$root/unpushed" ] || scenario_fail 'an unpushed commit must survive'
  [ -d "$root/dirty" ] || scenario_fail 'an uncommitted change must survive'
  [ -d "$root/live-worktree" ] \
    || scenario_fail 'a directory that is not a Git checkout must survive'
  # The checkout path reaches Git as an argument. Held in a command string and
  # expanded unquoted, a path with a space arrived as two arguments and every
  # question about it failed, which reads as "holding work" and keeps it.
  [ ! -d "$root/spaced name" ] \
    || scenario_fail 'a path containing a space must be judged like any other'
  assert_contains "$fixture/stdout.log" 'retired 2 agent worktree checkout(s)'
}

# A read-only subtree is what a build cache routinely holds -- a downloader
# that caches a signed application bundle writes it back read-only -- and the
# first rm -rf leaves the whole thing standing. The report used to add up the
# bytes before removing anything and print the total either way, so a run that
# freed nothing still said it had freed the directory.
test_fix_reports_only_the_artifacts_it_could_remove() {
  local fixture artifact_root
  fixture=$(make_fixture)
  artifact_root=$fixture/data/worktree/project/live-worktree/.opencode-artifacts
  mkdir -p "$artifact_root/idle/locked"
  printf 'signed\n' >"$artifact_root/idle/locked/bundle"
  chmod -w "$artifact_root/idle/locked"
  touch -t "$(date -r $(($(date +%s) - 30 * 86400)) +%Y%m%d%H%M)" \
    "$artifact_root/idle/locked/bundle" "$artifact_root/idle/locked" "$artifact_root/idle"
  invoke_doctor "$fixture" --fix

  [ ! -d "$artifact_root/idle" ] \
    || scenario_fail 'a read-only subtree must not stop the retirement'
  assert_contains "$fixture/stdout.log" 'retired 1 delegation artifact directory(ies)'
  assert_not_contains "$fixture/stderr.log" 'could not retire'
}

scenario_run 'a report counts artifacts and names the large ones' test_report_counts_artifacts_and_names_the_large_ones
scenario_run 'a repair retires only idle artifact directories' test_fix_retires_only_idle_artifact_directories
scenario_run 'zero retention retires every artifact directory' test_days_zero_retires_every_artifact_directory
scenario_run 'a repair removes only workspaces whose directory is gone' test_fix_removes_only_workspaces_whose_directory_is_gone
scenario_run 'a report names worktree checkouts without retiring them' test_report_names_worktree_checkouts_without_retiring_them
scenario_run 'a repair retires only reconstructible worktree checkouts' test_fix_retires_only_reconstructible_worktree_checkouts
scenario_run 'a repair reports only the artifacts it could remove' test_fix_reports_only_the_artifacts_it_could_remove
scenario_run 'a repair reaps a process left inside a worktree' test_fix_reaps_a_process_left_inside_a_worktree
scenario_run 'a repair refuses while the database is held' test_fix_refuses_while_the_database_is_held
scenario_run 'a repeated repair changes nothing further' test_repeat_repair_changes_nothing_further
scenario_run 'an oversized log is rotated' test_oversized_log_is_rotated
scenario_run 'a small log is left alone' test_small_log_is_left_alone
scenario_run 'zero retention and explicit log clearing preserve transcripts and unrelated files' test_zero_retention_and_log_clear_preserve_transcripts_and_other_files
scenario_run 'log clearing refuses a symlinked directory before changing state' test_log_clear_refuses_a_symlinked_directory
scenario_run 'an invalid retention window is a usage error' test_invalid_retention_is_a_usage_error
scenario_run 'a missing database is an operational error' test_missing_database_is_an_operational_error
scenario_run 'the fixture schema satisfies what the store declares' test_fixture_schema_satisfies_the_store_declaration
scenario_run 'each condition confirms a complete retirement' test_each_condition_confirms_a_complete_retirement
scenario_run 'each condition recovers with one permission repair' test_each_condition_recovers_with_one_permission_repair
scenario_run 'a failed permission repair keeps the directory and says so' test_a_failed_permission_repair_keeps_the_directory_and_says_so
scenario_run 'each condition fails a persistent removal and continues' test_each_condition_fails_a_persistent_removal_and_continues
scenario_run 'a partial removal counts neither directory nor bytes' test_a_partial_removal_counts_neither_directory_nor_bytes
scenario_run 'a removal that claims success is not a retirement' test_a_removal_that_claims_success_is_not_a_retirement
scenario_run 'an unmeasured directory is kept for the whole run' test_an_unmeasured_directory_is_kept_for_the_whole_run
scenario_run 'a directory gone before action is neither counted nor failed' test_a_directory_gone_before_action_is_neither_counted_nor_failed
scenario_run 'a directory replaced before action is kept' test_a_directory_replaced_before_action_is_kept
scenario_run 'a failed artifact keeps its checkout under zero retention' test_a_failed_artifact_keeps_its_checkout_under_zero_retention
scenario_run 'an artifact retired before its checkout is counted once' test_an_artifact_retired_before_its_checkout_is_counted_once
scenario_run 'a retired linked worktree leaves no registration' test_a_retired_linked_worktree_leaves_no_registration
scenario_run 'an unidentified owner keeps the linked checkout' test_an_unidentified_owner_keeps_the_linked_checkout
scenario_run 'a failed registration cleanup keeps the retirement and fails' test_a_failed_registration_cleanup_keeps_the_retirement_and_fails
scenario_run 'a registration left behind is named only by the run that knew it' test_a_registration_left_behind_is_named_only_by_the_run_that_knew_it
scenario_run 'a retired clone owes no registration cleanup' test_a_retired_clone_owes_no_registration_cleanup
scenario_run 'a kept snapshot parent does not undo the retirement' test_a_kept_snapshot_parent_does_not_undo_the_retirement
scenario_run 'a partial removal is not resumed by a later run' test_a_partial_removal_is_not_resumed_by_a_later_run
scenario_run 'a fatal condition still stops the run' test_a_fatal_condition_still_stops_the_run

scenario_finish
