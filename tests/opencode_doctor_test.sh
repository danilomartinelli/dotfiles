#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/stubs.sh
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
  local fixture now recent stale
  fixture=$(installer_fixture opencode-doctor)
  now=$(($(date +%s) * 1000))
  recent=$now
  stale=$((now - 30 * 86400 * 1000))

  mkdir -p "$fixture/data/log" "$fixture/config" \
    "$fixture/data/worktree/project/live-worktree"

  sqlite3 "$fixture/data/opencode.db" <<EOF
CREATE TABLE session (id text PRIMARY KEY, time_updated integer NOT NULL);
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
  ('ses_recent', $recent), ('ses_cut', $recent), ('ses_done', $recent),
  ('ses_stale', $stale);
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

  if [ "${1-}" = --artifacts ]; then
    artifacts=(--artifacts "$2")
    shift 2
  fi

  fixture_run "$fixture" ${artifacts[@]+"${artifacts[@]}"} \
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
  : >"$fixture/config/opencode.jsonc.openchamber.backup"
  invoke_doctor "$fixture"

  assert_contains "$fixture/stderr.log" "$fixture/config/opencode.json"
  assert_contains "$fixture/stderr.log" "$fixture/config/opencode.jsonc.openchamber.backup"
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

  assert_fails_with_status 1 invoke_doctor "$fixture" --fix
  stop_process "$pid"

  assert_contains "$fixture/stderr.log" 'OpenCode is running and holds the database'
  assert_equal '8' "$(count_rows "$fixture" 'SELECT count(*) FROM event;')" \
    'events after a refused repair'
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

scenario_run 'a report names state without changing it' test_report_names_state_without_changing_it
scenario_run 'an untracked shadowing config is reported' test_untracked_shadowing_config_is_reported
scenario_run 'a clean config directory reports nothing' test_clean_config_directory_is_not_reported
scenario_run 'a repair prunes finished and stale sessions only' test_fix_prunes_finished_and_stale_sessions_only
scenario_run 'the retention window protects only unfinished sessions' test_retention_window_is_selectable
scenario_run 'a repair removes only workspaces whose directory is gone' test_fix_removes_only_workspaces_whose_directory_is_gone
scenario_run 'a repair reaps a process left inside a worktree' test_fix_reaps_a_process_left_inside_a_worktree
scenario_run 'a repair refuses while the database is held' test_fix_refuses_while_the_database_is_held
scenario_run 'a repeated repair changes nothing further' test_repeat_repair_changes_nothing_further
scenario_run 'an oversized log is rotated' test_oversized_log_is_rotated
scenario_run 'a small log is left alone' test_small_log_is_left_alone
scenario_run 'an invalid retention window is a usage error' test_invalid_retention_is_a_usage_error
scenario_run 'a missing database is an operational error' test_missing_database_is_an_operational_error
scenario_finish
