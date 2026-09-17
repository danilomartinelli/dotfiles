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
  local fixture=$1 root checkout month
  root=$fixture/data/worktree/project
  month=$(date -r $(($(date +%s) - 30 * 86400)) +%Y%m%d%H%M)

  # One origin per checkout. Sharing a single bare repository made the second
  # and third pushes non-fast-forward rejections, which left those checkouts
  # holding work for a reason the scenario never meant to arrange.
  for checkout in pushed unpushed dirty 'spaced name'; do
    git -c init.defaultBranch=main init --quiet --bare "$fixture/$checkout.git"
    git -c init.defaultBranch=main init --quiet "$root/$checkout"
    git -C "$root/$checkout" config user.email fixture@example.invalid
    git -C "$root/$checkout" config user.name Fixture
    printf 'source\n' >"$root/$checkout/file.txt"
    git -C "$root/$checkout" add file.txt
    git -C "$root/$checkout" commit --quiet -m 'fixture'
    git -C "$root/$checkout" remote add origin "$fixture/$checkout.git"
    git -C "$root/$checkout" push --quiet -u origin main
  done

  printf 'local only\n' >"$root/unpushed/file.txt"
  git -C "$root/unpushed" commit --quiet -am 'local only'
  printf 'uncommitted\n' >"$root/dirty/file.txt"

  # -depth so children are touched before their parents: touching a file
  # inside a directory bumps that directory's own mtime back to now, and a
  # single stale file anywhere is enough to keep the checkout out of the
  # retention window.
  for checkout in pushed unpushed dirty 'spaced name'; do
    find "$root/$checkout" -depth -exec touch -t "$month" {} +
  done
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
scenario_finish
