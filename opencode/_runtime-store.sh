#!/bin/sh
#
# The one way into OpenCode's runtime database.
#
# The doctor reads and writes a database OpenCode owns. Reads used to go
# through a read-only adapter and writes went straight to sqlite3, so the one
# invariant the adapter encoded — a report can never be the thing that damages
# the database — held on one half and was absent on the other. The retention
# rule lived as shell strings spliced into three statements, the row shape was
# invented at each call site by joining columns on a tab inside SQL, and the
# schema this module depends on was written down only in a test.
#
# All four live here now. Open the store once, then ask it questions; writes
# stay refused until a caller has established that OpenCode is not running.
#
# Usage:
#   runtime_store_open <data-dir> <retention-days>
#   runtime_store_permit_writes

# The tables and columns this module reads. OpenCode owns the schema and may
# change it; declaring the dependency turns "the doctor quietly stops finding
# anything" into a refusal that names the column that went away.
# docs/adr/0016-the-runtime-store-declares-a-schema-it-does-not-own.md
RUNTIME_STORE_SCHEMA='session:id,workspace_id,time_updated
message:session_id,time_created,data
event:aggregate_id
event_sequence:aggregate_id
workspace:id,type,directory'

RUNTIME_STORE_WRITABLE=0

# Open the store against <data-dir>, verify the schema, and fix the retention
# window for the rest of the run. Fails when there is no database to inspect.
runtime_store_open() {
  RUNTIME_STORE_PATH=$1/opencode.db
  RUNTIME_STORE_RETENTION_DAYS=$2

  if [ ! -f "$RUNTIME_STORE_PATH" ]; then
    installer_error "no OpenCode database at $RUNTIME_STORE_PATH"
    installer_hint 'Run OpenCode once, or pass --data-dir for a different data directory.'
    exit 1
  fi

  RUNTIME_STORE_CUTOFF_MS=$((($(date +%s) - RUNTIME_STORE_RETENTION_DAYS * 86400) * 1000))
  _runtime_store_verify_schema
  _runtime_store_compose_retention
}

# Every write is refused until the caller has established that nothing else
# holds the database. The guard is on the write rather than at the top of a
# run, so a new repair cannot be added on the wrong side of it.
runtime_store_permit_writes() {
  RUNTIME_STORE_WRITABLE=1
}

runtime_store_path() {
  printf '%s\n' "$RUNTIME_STORE_PATH"
}

# The processes holding the database. Any of them means OpenCode is up.
runtime_store_holders() {
  lsof -t -- "$RUNTIME_STORE_PATH" 2>/dev/null || true
}

_runtime_store_read() {
  sqlite3 "file:$RUNTIME_STORE_PATH?mode=ro" "$1"
}

_runtime_store_write() {
  if [ "$RUNTIME_STORE_WRITABLE" -ne 1 ]; then
    installer_error 'refusing to write to the OpenCode database before it is known to be idle'
    exit 1
  fi
  sqlite3 "$RUNTIME_STORE_PATH" "$1"
}

# Refuse on the first missing table or column rather than reporting nothing.
# The loop reads from a here-document so its refusal exits the run, which it
# could not do from the subshell a pipeline would put it in.
_runtime_store_verify_schema() {
  while IFS=: read -r table columns; do
    [ -n "$table" ] || continue
    present=$(_runtime_store_read "SELECT group_concat(name) FROM pragma_table_info('$table');")
    if [ -z "$present" ]; then
      installer_error "the OpenCode database has no $table table"
      installer_hint 'OpenCode changed its schema; opencode/_runtime-store.sh declares what this needs.'
      exit 1
    fi

    for column in $(printf '%s' "$columns" | tr ',' ' '); do
      case ",$present," in
        *",$column,"*) ;;
        *)
          installer_error "the OpenCode $table table has no $column column"
          installer_hint 'OpenCode changed its schema; opencode/_runtime-store.sh declares what this needs.'
          exit 1
          ;;
      esac
    done
  done <<EOF
$RUNTIME_STORE_SCHEMA
EOF
}

# A session is finished when its newest message is an assistant reply that
# reached completion. One the model never completed was interrupted and may be
# resumed, and one whose newest message is a prompt is still owed a reply.
#
# The message index on (session_id, time_created) answers the newest-message
# lookup per session without touching message bodies beyond that one row.
#
# Which sessions still need their replication history: the unfinished ones
# inside the retention window. Every other aggregate is prunable.
# `event_sequence` holds one small row per session, so naming the aggregates
# there and matching them through the event log's own index answers an exact
# count without scanning the large event payloads.
#
# The sequence rows themselves stay. They are tiny, and keeping one means the
# seq a session reached never restarts below a number some replica already saw.
_runtime_store_compose_retention() {
  # A zero-day window retains nothing, and no comparison against a cutoff can
  # say that: a session updated in the current second, or carrying a timestamp
  # ahead of this machine's clock, is still newer than "now". The full sweep is
  # the rule for an empty window rather than an exception to it.
  if [ "$RUNTIME_STORE_RETENTION_DAYS" -eq 0 ]; then
    RUNTIME_STORE_PRUNABLE='SELECT aggregate_id FROM event_sequence'
    return 0
  fi

  RUNTIME_STORE_PRUNABLE="SELECT aggregate_id FROM event_sequence
    WHERE aggregate_id NOT IN (
      SELECT id FROM session
      WHERE time_updated >= $RUNTIME_STORE_CUTOFF_MS AND id NOT IN (
        SELECT id FROM session AS finished
        WHERE (SELECT json_extract(data, '\$.role') = 'assistant'
                 AND json_extract(data, '\$.time.completed') IS NOT NULL
               FROM message WHERE session_id = finished.id
               ORDER BY time_created DESC LIMIT 1)))"
}

runtime_store_prunable_event_count() {
  _runtime_store_read "SELECT count(*) FROM event WHERE aggregate_id IN ($RUNTIME_STORE_PRUNABLE);"
}

runtime_store_prune_events() {
  _runtime_store_write "DELETE FROM event WHERE aggregate_id IN ($RUNTIME_STORE_PRUNABLE);"
  _runtime_store_write 'VACUUM;'
}

# One workspace row per line as id, type, directory. The separator is sqlite's
# rather than a tab spliced into the projection, and the directory is last so a
# tab inside a path reaches the reader whole. A newline inside one cannot, so
# such a row is excluded here and named by runtime_store_unreadable_workspaces
# instead of silently arriving as two corrupt rows.
runtime_store_workspace_rows() {
  _runtime_store_read_rows "SELECT id, type, directory FROM workspace
    WHERE directory IS NOT NULL AND instr(directory, char(10)) = 0;"
}

runtime_store_unreadable_workspaces() {
  _runtime_store_read "SELECT count(*) FROM workspace
    WHERE directory IS NOT NULL AND instr(directory, char(10)) > 0;"
}

_runtime_store_read_rows() {
  sqlite3 -separator "$(printf '\t')" "file:$RUNTIME_STORE_PATH?mode=ro" "$1"
}

# The id is checked against the character class the schema produces rather than
# quoted, because this is the one place a value from the database is named in a
# statement and a refusal is cheaper to read than an escaping rule.
runtime_store_delete_workspace() {
  case $1 in
    '' | *[!A-Za-z0-9_-]*)
      installer_warn "skipping workspace row with an unexpected id: $1"
      return 1
      ;;
  esac
  _runtime_store_write "DELETE FROM workspace WHERE id = '$1';"
}

# A session pointing at a workspace row that no longer exists. Every delete and
# archive resolves the workspace first, so the session is stranded in the UI
# until the reference goes; a null id is what a session without one already
# carries, and those delete normally.
RUNTIME_STORE_DANGLING="workspace_id IS NOT NULL
  AND workspace_id NOT IN (SELECT id FROM workspace)"

runtime_store_dangling_session_count() {
  _runtime_store_read "SELECT count(*) FROM session WHERE $RUNTIME_STORE_DANGLING;"
}

runtime_store_release_dangling_sessions() {
  _runtime_store_write "UPDATE session SET workspace_id = NULL WHERE $RUNTIME_STORE_DANGLING;"
}
