#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-opencode-runtime-store-tests

STORE=$REPOSITORY_ROOT/opencode/_runtime-store.sh
OUTPUT=$REPOSITORY_ROOT/_scripts/installer-output.sh

# The columns the store declares it depends on, in the shape a CREATE TABLE
# fixture has to satisfy. The declaration is the module's, so a schema the
# doctor suite hand-writes and this one hand-writes cannot drift apart from it
# without one of them saying so.
schema_declaration() {
  sed -n "/^RUNTIME_STORE_SCHEMA='/,/'$/p" "$STORE" \
    | sed "s/^RUNTIME_STORE_SCHEMA='//; s/'$//" | grep -v '^$'
}

# A database carrying everything the store declares, so a scenario that wants
# one column missing can say so by naming it rather than by restating a schema.
make_database() {
  local path=$1
  local omit=${2-}

  sqlite3 "$path" <<EOF
CREATE TABLE session (id text PRIMARY KEY, workspace_id text, time_updated integer NOT NULL);
CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, data text NOT NULL);
CREATE TABLE event_sequence (aggregate_id text PRIMARY KEY, seq integer NOT NULL);
CREATE TABLE event (id text PRIMARY KEY, aggregate_id text NOT NULL, seq integer NOT NULL);
CREATE TABLE workspace (id text PRIMARY KEY, type text NOT NULL, directory text);
EOF

  case $omit in
    '') ;;
    workspace-table) sqlite3 "$path" 'DROP TABLE workspace;' ;;
    session-column) sqlite3 "$path" 'ALTER TABLE session DROP COLUMN time_updated;' ;;
    *) scenario_fail "unknown omission: $omit" ;;
  esac
}

# Run <body> with the store sourced and opened against the fixture database,
# the way the doctor reaches it. Opening is part of the body so a scenario can
# assert on the refusal opening itself produces.
invoke_store() {
  local fixture=$1
  local body=$2
  local retention=${3-7}

  cat >"$fixture/consumer.sh" <<EOF
#!/bin/sh
set -eu
. "$OUTPUT"
. "$STORE"
runtime_store_open "$fixture/data" $retention
$body
EOF
  chmod +x "$fixture/consumer.sh"
  scenario_capture "$fixture" env PATH="/usr/bin:/bin" "$fixture/consumer.sh"
}

new_fixture() {
  local fixture omit=${1-}
  fixture=$(scenario_tmpdir store)
  mkdir -p "$fixture/data"
  make_database "$fixture/data/opencode.db" "$omit"
  printf '%s\n' "$fixture"
}

# The declaration is the point of the module: without it a schema change
# upstream turns every condition into "nothing found" rather than a refusal.
test_a_missing_table_is_refused_by_name() {
  local fixture
  fixture=$(new_fixture workspace-table)

  assert_fails 'opening refuses a missing table' \
    invoke_store "$fixture" 'runtime_store_workspace_rows'
  assert_contains "$fixture/stderr.log" 'has no workspace table'
}

test_a_missing_column_is_refused_by_name() {
  local fixture
  fixture=$(new_fixture session-column)

  assert_fails 'opening refuses a missing column' \
    invoke_store "$fixture" 'runtime_store_dangling_session_count'
  assert_contains "$fixture/stderr.log" 'has no time_updated column'
}

test_a_declared_schema_is_satisfied_by_the_fixture() {
  local fixture table columns column present
  fixture=$(new_fixture)

  while IFS=: read -r table columns; do
    [ -n "$table" ] || continue
    present=$(sqlite3 "$fixture/data/opencode.db" \
      "SELECT group_concat(name) FROM pragma_table_info('$table');")
    for column in ${columns//,/ }; do
      case ",$present," in
        *",$column,"*) ;;
        *) scenario_fail "fixture schema lacks $table.$column" || return 1 ;;
      esac
    done
  done < <(schema_declaration)
}

# The guard is on the write rather than at the top of a run, so a repair added
# later cannot land on the wrong side of the idle check.
test_a_write_before_permission_is_refused() {
  local fixture
  fixture=$(new_fixture)

  assert_fails 'an unpermitted write refuses' \
    invoke_store "$fixture" 'runtime_store_release_dangling_sessions'
  assert_contains "$fixture/stderr.log" 'before it is known to be idle'
}

test_a_permitted_write_proceeds() {
  local fixture
  fixture=$(new_fixture)

  sqlite3 "$fixture/data/opencode.db" \
    "INSERT INTO session VALUES ('ses_one', 'wrk_gone', 1);"
  invoke_store "$fixture" \
    'runtime_store_permit_writes
runtime_store_release_dangling_sessions
runtime_store_dangling_session_count'
  assert_contains "$fixture/stdout.log" '0'
  assert_equal '' \
    "$(sqlite3 "$fixture/data/opencode.db" \
      'SELECT workspace_id FROM session WHERE id = "ses_one";')" \
    'a released session keeps no workspace reference'
}

# The row shape used to be a tab spliced into the projection and split back out
# in shell. A directory is the one column an arbitrary filesystem path lands
# in, so it is last and arrives whole.
test_a_directory_containing_a_tab_arrives_whole() {
  local fixture
  fixture=$(new_fixture)

  sqlite3 "$fixture/data/opencode.db" \
    "INSERT INTO workspace VALUES ('wrk_tab', 'worktree', '/tmp/two	words');"
  invoke_store "$fixture" 'runtime_store_workspace_rows'
  assert_contains "$fixture/stdout.log" '/tmp/two	words'
}

# A newline cannot survive a line-oriented reader, so such a row is excluded
# and counted rather than delivered as two corrupt ones.
test_a_directory_containing_a_newline_is_named_not_split() {
  local fixture
  fixture=$(new_fixture)

  sqlite3 "$fixture/data/opencode.db" \
    "INSERT INTO workspace VALUES ('wrk_nl', 'worktree', '/tmp/two' || char(10) || 'lines');"
  invoke_store "$fixture" \
    'runtime_store_workspace_rows
runtime_store_unreadable_workspaces'
  assert_not_contains "$fixture/stdout.log" 'wrk_nl'
  assert_contains "$fixture/stdout.log" '1'
}

test_an_unexpected_workspace_id_is_refused() {
  local fixture
  fixture=$(new_fixture)

  invoke_store "$fixture" \
    "runtime_store_permit_writes
runtime_store_delete_workspace \"bad'id\" || printf 'refused\n'"
  assert_contains "$fixture/stderr.log" 'unexpected id'
  assert_contains "$fixture/stdout.log" 'refused'
}

# Sessions carrying the shapes the retention rule distinguishes: one finished,
# one still owed a reply inside the window, and one long past it.
seed_retention() {
  local fixture=$1
  local now recent stale
  now=$(($(date +%s) * 1000))
  recent=$now
  stale=$((now - 30 * 86400 * 1000))

  sqlite3 "$fixture/data/opencode.db" <<EOF
INSERT INTO session VALUES ('ses_open', NULL, $recent), ('ses_done', NULL, $recent),
  ('ses_old', NULL, $stale);
INSERT INTO message VALUES
  ('m1', 'ses_open', 1, '{"role":"user","time":{"created":1}}'),
  ('m2', 'ses_done', 1, '{"role":"assistant","time":{"created":1,"completed":2}}'),
  ('m3', 'ses_old', 1, '{"role":"user","time":{"created":1}}');
INSERT INTO event_sequence VALUES ('ses_open', 1), ('ses_done', 1), ('ses_old', 1);
INSERT INTO event VALUES ('e1', 'ses_open', 1), ('e2', 'ses_done', 1), ('e3', 'ses_old', 1);
EOF
}

test_the_window_retains_only_unfinished_sessions_inside_it() {
  local fixture
  fixture=$(new_fixture)
  seed_retention "$fixture"

  invoke_store "$fixture" 'runtime_store_prunable_event_count' 7
  assert_contains "$fixture/stdout.log" '2'
}

# A zero-width window retains nothing, which no comparison against a cutoff can
# say: a session updated in the current second, or carrying a timestamp ahead
# of this machine's clock, is still newer than "now". This is what the README
# promises --days 0 does, and the only thing that proves the full sweep is the
# rule for an empty window rather than an exception to it.
test_zero_retention_prunes_events_of_a_session_updated_ahead_of_the_clock() {
  local fixture ahead
  fixture=$(new_fixture)
  seed_retention "$fixture"
  ahead=$((($(date +%s) + 86400) * 1000))
  sqlite3 "$fixture/data/opencode.db" <<EOF
INSERT INTO session VALUES ('ses_ahead', NULL, $ahead);
INSERT INTO message VALUES ('m4', 'ses_ahead', 1, '{"role":"user","time":{"created":1}}');
INSERT INTO event_sequence VALUES ('ses_ahead', 1);
INSERT INTO event VALUES ('e4', 'ses_ahead', 1);
EOF

  invoke_store "$fixture" 'runtime_store_prunable_event_count' 0
  assert_contains "$fixture/stdout.log" '4'

  invoke_store "$fixture" \
    'runtime_store_permit_writes
runtime_store_prune_events
runtime_store_prunable_event_count' 0
  assert_contains "$fixture/stdout.log" '0'
  assert_equal '4' \
    "$(sqlite3 "$fixture/data/opencode.db" 'SELECT count(*) FROM message;')" \
    'pruning replication events keeps every transcript'
}

test_a_missing_database_is_an_operational_error() {
  local fixture
  fixture=$(scenario_tmpdir store-empty)
  mkdir -p "$fixture/data"

  assert_fails 'opening refuses a missing database' \
    invoke_store "$fixture" 'runtime_store_path'
  assert_contains "$fixture/stderr.log" 'no OpenCode database at'
}

scenario_run 'a missing table is refused by name' \
  test_a_missing_table_is_refused_by_name
scenario_run 'a missing column is refused by name' \
  test_a_missing_column_is_refused_by_name
scenario_run 'the declared schema is satisfied by a fixture' \
  test_a_declared_schema_is_satisfied_by_the_fixture
scenario_run 'a write before permission is refused' \
  test_a_write_before_permission_is_refused
scenario_run 'a permitted write proceeds' \
  test_a_permitted_write_proceeds
scenario_run 'a directory containing a tab arrives whole' \
  test_a_directory_containing_a_tab_arrives_whole
scenario_run 'a directory containing a newline is named, not split' \
  test_a_directory_containing_a_newline_is_named_not_split
scenario_run 'an unexpected workspace id is refused' \
  test_an_unexpected_workspace_id_is_refused
scenario_run 'the window retains only unfinished sessions inside it' \
  test_the_window_retains_only_unfinished_sessions_inside_it
scenario_run 'zero retention prunes a session ahead of the clock' \
  test_zero_retention_prunes_events_of_a_session_updated_ahead_of_the_clock
scenario_run 'a missing database is an operational error' \
  test_a_missing_database_is_an_operational_error

scenario_finish
