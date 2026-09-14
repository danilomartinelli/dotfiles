#!/bin/sh
#
# Report and repair the OpenCode runtime state that nothing else owns.
#
# install.sh links the tracked half of OpenCode into ~/.config/opencode. The
# other half is the data directory, and OpenCode prunes none of it:
#
#   - `event` is an append-only replication log for remote workspaces. Every
#     streaming update of a message part is stored as a fresh copy of the whole
#     part, so one long session writes its own transcript back many times over.
#     `message` and `part` retain the transcript independently. A session whose
#     newest message is a completed assistant reply has nothing left to
#     replicate, so its events are prunable at any age; only a session still
#     waiting for or writing a reply keeps them, and only within the window.
#   - A command an agent started inside a worktree outlives the session that
#     started it.
#   - A `workspace` row outlives the directory it describes, and a row written
#     by an OCX component that is no longer installed fails every server start
#     with "Unknown workspace adapter".
#   - A session snapshot is a Git directory shadowing the directory its
#     `core.worktree` names. When that directory goes, OpenCode keeps trying to
#     collect garbage inside it; one leftover wrote 39 warnings in a day.
#   - A delegation's artifact directory is created per delegation and kept for
#     as long as the worktree lives. The orchestrator cannot retire it on its
#     own: it has no way to tell a screenshot from an Xcode DerivedData tree,
#     so it preserves both. Verification work puts build output there because
#     an `ownership: []` delegation has nowhere else to write.
#
# Reporting is the default because every repair deletes state no backup covers.
# Repairs need --fix and refuse to run while OpenCode holds the database. That
# one precondition is also what makes reaping safe to state: a process still
# living inside an agent worktree while no OpenCode runs has no owner left to
# lose, so no ancestry heuristic has to decide it.
#
# A shadowing configuration file is reported and never removed. Which global
# config a machine should carry is a policy question this module has no
# standing to answer; naming the file that OpenCode merges behind the tracked
# one is the whole contribution.

set -eu

SCRIPT_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)

# shellcheck source=_scripts/installer-output.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../_scripts/installer-output.sh"

# shellcheck source=_scripts/catalog.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../_scripts/catalog.sh"

MANAGED_ENTRIES=$SCRIPT_DIR/_managed-entries.tsv

# OpenCode resolves its data directory through XDG_DATA_HOME and names that
# variable in its own diagnostics, which is the tool stating its own fact.
# docs/adr/0003-tool-config-directories-are-not-xdg-derived.md governs the
# configuration directory below, and it is spelled the way that ADR requires.
DATA_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/opencode
CONFIG_DIR=$HOME/.config/opencode
RETENTION_DAYS=7
FIX=0
CLEAR_LOGS=0

# Keep one rotation of an oversized primary log during routine repairs.
LOG_ROTATE_BYTES=67108864

# Name a delegation's artifacts individually once they are large enough to
# matter beside the database; smaller ones still count toward the total. It is
# overridable for the same reason --data-dir is: so a fixture can exercise the
# threshold without writing a gigabyte per scenario.
ARTIFACT_REPORT_BYTES=${ARTIFACT_REPORT_BYTES:-1073741824}

usage() {
  cat >&2 <<'EOF'
Usage: opencode/_doctor.sh [--fix] [--days <n>] [--clear-logs] [--data-dir <dir>] [--config-dir <dir>]

--days <n>     Retention window for replication events and delegation artifacts.
--days 0       Prune and retire both, including today's; keep transcripts.
--clear-logs   With --fix, delete log files and rotations regardless of age or size.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fix)
      FIX=1
      shift
      ;;
    --clear-logs)
      CLEAR_LOGS=1
      shift
      ;;
    --days)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      RETENTION_DAYS=$2
      shift 2
      ;;
    --data-dir)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      DATA_DIR=$2
      shift 2
      ;;
    --config-dir)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      CONFIG_DIR=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

case $RETENTION_DAYS in
  '' | *[!0-9]*)
    installer_error "--days expects a whole number of days: $RETENTION_DAYS"
    exit 2
    ;;
esac

DATABASE=$DATA_DIR/opencode.db
LOG_FILE=$DATA_DIR/log/opencode.log
WORKTREE_ROOT=$DATA_DIR/worktree
SNAPSHOT_ROOT=$DATA_DIR/snapshot
CUTOFF_MS=$((($(date +%s) - RETENTION_DAYS * 86400) * 1000))

require_command() {
  command -v "$1" >/dev/null 2>&1 && return 0
  installer_error "$1 is required to inspect the OpenCode data directory"
  installer_hint "$2"
  exit 1
}

require_command sqlite3 'It ships with macOS; check PATH before rerunning.'
require_command lsof 'It ships with macOS; check PATH before rerunning.'
require_command git 'Install the Command Line Tools, then rerun.'

# Read-only so a report can never be the thing that damages the database.
database_query() {
  sqlite3 "file:$DATABASE?mode=ro" "$1"
}

file_bytes() {
  [ -f "$1" ] || {
    printf '0\n'
    return 0
  }
  wc -c <"$1" | tr -d ' '
}

directory_bytes() {
  [ -d "$1" ] || {
    printf '0\n'
    return 0
  }
  du -sk -- "$1" 2>/dev/null | awk '{print $1 * 1024; exit}'
}

# Command substitution strips the trailing newline, so a list of n lines
# reaches wc as n-1 newlines unless one is put back.
line_count() {
  [ -n "$1" ] || {
    printf '0\n'
    return 0
  }
  printf '%s\n' "$1" | wc -l | tr -d ' '
}

human_bytes() {
  awk -v bytes="$1" 'BEGIN {
    split("B KB MB GB TB", unit, " ")
    step = 1
    while (bytes >= 1024 && step < 5) {
      bytes /= 1024
      step++
    }
    printf (step == 1 ? "%d %s\n" : "%.1f %s\n"), bytes, unit[step]
  }'
}

# The processes that still hold the database. Any of them means OpenCode is up,
# and every repair below is refused while that is true.
database_holders() {
  [ -f "$DATABASE" ] || return 0
  lsof -t -- "$DATABASE" 2>/dev/null || true
}

# Processes whose working directory is inside an agent worktree. A child
# inherits its parent's directory, so a leaked tree matches through every one
# of its members and needs no separate descendant walk.
leaked_processes() {
  lsof -d cwd -Fpn 2>/dev/null | awk -v prefix="$WORKTREE_ROOT/" '
    /^p/ {
      pid = substr($0, 2)
      next
    }
    /^n/ {
      path = substr($0, 2)
      if (pid != "" && index(path, prefix) == 1) {
        print pid
      }
      pid = ""
    }
  '
}

# A session is finished when its newest message is an assistant reply that
# reached completion. One the model never completed was interrupted and may be
# resumed, and one whose newest message is a prompt is still owed a reply.
#
# The message index on (session_id, time_created) answers the newest-message
# lookup per session without touching message bodies beyond that one row.
FINISHED_SESSIONS="SELECT id FROM session AS finished
  WHERE (SELECT json_extract(data, '\$.role') = 'assistant'
           AND json_extract(data, '\$.time.completed') IS NOT NULL
         FROM message WHERE session_id = finished.id
         ORDER BY time_created DESC LIMIT 1)"

# Which sessions still need their replication history: the unfinished ones
# inside the retention window. Every other aggregate is prunable.
# `event_sequence` holds one small row per session, so naming the aggregates
# there and matching them through the event log's own index answers an exact
# count without scanning the large event payloads.
#
# The sequence rows themselves stay. They are tiny, and keeping one means the
# seq a session reached never restarts below a number some replica already saw.
PRUNABLE_AGGREGATES="SELECT aggregate_id FROM event_sequence
  WHERE aggregate_id NOT IN (
    SELECT id FROM session
    WHERE time_updated >= $CUTOFF_MS AND id NOT IN ($FINISHED_SESSIONS))"

# Zero is an explicit full replication-log cleanup, including timestamps in
# the current second or ahead of this machine's clock. Transcripts stay intact.
if [ "$RETENTION_DAYS" -eq 0 ]; then
  PRUNABLE_AGGREGATES='SELECT aggregate_id FROM event_sequence'
fi

prunable_event_count() {
  database_query "SELECT count(*) FROM event WHERE aggregate_id IN ($PRUNABLE_AGGREGATES);"
}

# A workspace row whose directory is gone describes nothing a session can be
# resumed into, and it is the shape the rows with a retired adapter took.
stale_workspaces() {
  database_query "SELECT id || '	' || type || '	' || directory FROM workspace;" \
    | while IFS="$(printf '\t')" read -r workspace_id workspace_type workspace_directory; do
      [ -n "$workspace_directory" ] || continue
      [ ! -d "$workspace_directory" ] || continue
      printf '%s\t%s\t%s\n' "$workspace_id" "$workspace_type" "$workspace_directory"
    done
}

# A snapshot Git directory naming a directory that is gone. Reading the answer
# out of the snapshot's own core.worktree keeps the rule true for a session in
# a checkout of the user's own, not only for an agent worktree. A snapshot
# whose config names no worktree is left alone: nothing here can judge it.
stale_snapshots() {
  [ -d "$SNAPSHOT_ROOT" ] || return 0
  find "$SNAPSHOT_ROOT" -mindepth 2 -maxdepth 2 -type d 2>/dev/null \
    | while IFS= read -r snapshot_dir; do
      snapshot_worktree=$(git --git-dir "$snapshot_dir" config --get core.worktree 2>/dev/null) \
        || continue
      [ -n "$snapshot_worktree" ] || continue
      [ ! -d "$snapshot_worktree" ] || continue
      printf '%s\t%s\n' "$snapshot_dir" "$snapshot_worktree"
    done
}

# One directory per delegation, below the artifact root each worktree carries.
# The search stays inside the data directory: an artifact directory a session
# created in a checkout of the user's own is part of that checkout, visible in
# its own status, and not this module's to retire.
artifact_directories() {
  [ -d "$WORKTREE_ROOT" ] || return 0
  find "$WORKTREE_ROOT" -mindepth 3 -maxdepth 3 -type d \
    -name .opencode-artifacts 2>/dev/null \
    | while IFS= read -r artifact_root; do
      find "$artifact_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
    done
}

# Nothing has written to it inside the window, so no delegation is still adding
# to it. Loose evidence sitting directly in the artifact root belongs to no
# delegation and is never considered here. --days 0 retires every directory,
# the way it prunes every replication event.
#
# -mtime counts the same 24-hour periods the event cutoff does. It is used in
# place of -newermt because the BSD find on this platform rejects an epoch.
artifact_is_retired() {
  if [ "$RETENTION_DAYS" -eq 0 ]; then
    return 0
  fi
  [ -z "$(find "$1" -mtime -"$RETENTION_DAYS" -print -quit 2>/dev/null)" ]
}

# Every managed entry the installer links, so a shadowing sibling is judged
# against the catalog rather than against a list restated here.
collect_managed_entry() {
  entry_kind=$1
  entry_name=$2

  [ "$entry_kind" = entry ] || return 0
  MANAGED_ENTRY_NAMES="$MANAGED_ENTRY_NAMES$entry_name
"
  return 0
}

# OpenCode reads opencode.json as readily as opencode.jsonc, and merges what it
# finds, so an untracked twin of a managed entry changes the running
# configuration without appearing in any diff. A leftover suffixed copy is
# reported for the same reason: it is one rename away from being read.
shadowing_configs() {
  printf '%s' "$MANAGED_ENTRY_NAMES" | while IFS= read -r entry_name; do
    [ -n "$entry_name" ] || continue

    case $entry_name in
      *.jsonc)
        twin=$CONFIG_DIR/${entry_name%.jsonc}.json
        [ ! -f "$twin" ] || printf '%s\n' "$twin"
        ;;
    esac

    for leftover in "$CONFIG_DIR/$entry_name".*; do
      [ -e "$leftover" ] || continue
      case $leftover in
        "$CONFIG_DIR/$entry_name") continue ;;
      esac
      printf '%s\n' "$leftover"
    done
  done
}

report_database() {
  database_bytes=$(file_bytes "$DATABASE")
  prunable=$(prunable_event_count)

  installer_note "database $(human_bytes "$database_bytes") at $DATABASE"
  installer_note "prunable replication events (finished sessions, or idle for $RETENTION_DAYS days): $prunable"
}

report_log() {
  log_bytes=$(file_bytes "$LOG_FILE")
  installer_note "log $(human_bytes "$log_bytes") at $LOG_FILE"
}

report_processes() {
  leaked=$(leaked_processes)
  if [ -z "$leaked" ]; then
    installer_note 'no processes left inside an agent worktree'
    return 0
  fi

  installer_note "processes still inside an agent worktree: $(line_count "$leaked")"
  printf '%s\n' "$leaked" | while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    installer_note "pid $pid $(ps -o command= -p "$pid" 2>/dev/null | cut -c1-72)"
  done
}

report_workspaces() {
  stale=$(stale_workspaces)
  if [ -z "$stale" ]; then
    installer_note 'no workspace rows describe a missing directory'
    return 0
  fi

  printf '%s\n' "$stale" | while IFS="$(printf '\t')" read -r workspace_id workspace_type workspace_directory; do
    [ -n "$workspace_id" ] || continue
    installer_note "workspace $workspace_id ($workspace_type) lost $workspace_directory"
  done
}

report_snapshots() {
  snapshots=$(stale_snapshots)
  if [ -z "$snapshots" ]; then
    installer_note 'no session snapshots describe a missing directory'
    return 0
  fi

  installer_note "session snapshots whose directory is gone: $(line_count "$snapshots")"
  printf '%s\n' "$snapshots" | while IFS="$(printf '\t')" read -r snapshot_dir snapshot_worktree; do
    [ -n "$snapshot_dir" ] || continue
    installer_note "snapshot lost $snapshot_worktree"
  done
}

report_artifacts() {
  artifacts=$(artifact_directories)
  if [ -z "$artifacts" ]; then
    installer_note 'no delegation artifact directories'
    return 0
  fi

  artifact_total=0
  retired_total=0
  retired_count=0
  oversized=''
  while IFS= read -r artifact_dir; do
    [ -n "$artifact_dir" ] || continue
    artifact_bytes=$(directory_bytes "$artifact_dir")
    artifact_total=$((artifact_total + artifact_bytes))
    if artifact_is_retired "$artifact_dir"; then
      retired_total=$((retired_total + artifact_bytes))
      retired_count=$((retired_count + 1))
    fi
    [ "$artifact_bytes" -ge "$ARTIFACT_REPORT_BYTES" ] || continue
    oversized="$oversized$(printf '%s\t%s' "$(human_bytes "$artifact_bytes")" "$artifact_dir")
"
  done <<EOF
$artifacts
EOF

  installer_note "delegation artifacts $(human_bytes "$artifact_total") in $(line_count "$artifacts") directory(ies)"
  installer_note "retired artifacts (idle for $RETENTION_DAYS days): $retired_count, $(human_bytes "$retired_total")"
  printf '%s' "$oversized" | while IFS="$(printf '\t')" read -r artifact_size artifact_dir; do
    [ -n "$artifact_dir" ] || continue
    installer_note "artifacts $artifact_size at $artifact_dir"
  done
}

report_configs() {
  shadowing=$(shadowing_configs)
  if [ -z "$shadowing" ]; then
    installer_note 'no untracked configuration shadows a managed entry'
    return 0
  fi

  printf '%s\n' "$shadowing" | while IFS= read -r shadow_path; do
    [ -n "$shadow_path" ] || continue
    installer_warn "untracked configuration OpenCode also reads: $shadow_path"
    installer_hint 'Track what it declares in opencode/opencode.jsonc, then remove it.'
  done
}

require_stopped_opencode() {
  holders=$(database_holders)
  [ -n "$holders" ] || return 0

  installer_error 'OpenCode is running and holds the database'
  installer_hint "Quit OpenChamber and any opencode session, then rerun. Holding pids: $(printf '%s' "$holders" | tr '\n' ' ')"
  exit 1
}

repair_processes() {
  leaked=$(leaked_processes)
  [ -n "$leaked" ] || return 0

  printf '%s\n' "$leaked" | while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    kill -TERM "$pid" 2>/dev/null || true
  done

  waited=0
  while [ "$waited" -lt 5 ]; do
    [ -n "$(leaked_processes)" ] || break
    sleep 1
    waited=$((waited + 1))
  done

  leaked_processes | while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    kill -KILL "$pid" 2>/dev/null || true
  done

  installer_item "reaped $(line_count "$leaked") process(es) left inside an agent worktree"
}

repair_events() {
  prunable=$(prunable_event_count)
  if [ "$prunable" -eq 0 ]; then
    installer_note 'no prunable replication events'
    return 0
  fi

  before=$(file_bytes "$DATABASE")
  sqlite3 "$DATABASE" "DELETE FROM event WHERE aggregate_id IN ($PRUNABLE_AGGREGATES);"
  sqlite3 "$DATABASE" 'VACUUM;'
  after=$(file_bytes "$DATABASE")

  installer_item "pruned replication events of finished sessions and of sessions idle for $RETENTION_DAYS days"
  installer_item "database $(human_bytes "$before") to $(human_bytes "$after")"
}

repair_workspaces() {
  stale=$(stale_workspaces)
  [ -n "$stale" ] || return 0

  removed=0
  while IFS="$(printf '\t')" read -r workspace_id workspace_type workspace_directory; do
    [ -n "$workspace_id" ] || continue
    case $workspace_id in
      *[!A-Za-z0-9_-]*)
        installer_warn "skipping workspace row with an unexpected id: $workspace_id"
        continue
        ;;
    esac
    sqlite3 "$DATABASE" "DELETE FROM workspace WHERE id = '$workspace_id';"
    removed=$((removed + 1))
  done <<EOF
$stale
EOF

  [ "$removed" -eq 0 ] || installer_item "removed $removed workspace row(s) describing a missing directory"
}

# A snapshot whose directory is gone can never be restored into, so it goes
# whole rather than by retention. The hash directory above it is removed only
# when the last snapshot under it leaves.
repair_snapshots() {
  snapshots=$(stale_snapshots)
  [ -n "$snapshots" ] || return 0

  removed=0
  removed_bytes=0
  while IFS="$(printf '\t')" read -r snapshot_dir snapshot_worktree; do
    [ -n "$snapshot_dir" ] || continue
    case $snapshot_dir in
      "$SNAPSHOT_ROOT"/*) ;;
      *)
        installer_warn "skipping a snapshot path outside the snapshot root: $snapshot_dir"
        continue
        ;;
    esac
    [ ! -L "$snapshot_dir" ] || continue
    removed_bytes=$((removed_bytes + $(directory_bytes "$snapshot_dir")))
    rm -rf -- "$snapshot_dir"
    rmdir -- "$(dirname -- "$snapshot_dir")" 2>/dev/null || true
    removed=$((removed + 1))
  done <<EOF
$snapshots
EOF

  [ "$removed" -eq 0 ] \
    || installer_item "removed $removed session snapshot(s) describing a missing directory, $(human_bytes "$removed_bytes")"
}

# Retiring a directory takes its evidence with it, which is the whole point of
# requiring --fix. The path guard is against a malformed list rather than a
# depth proof: everything here came from a search rooted in the data directory.
repair_artifacts() {
  artifacts=$(artifact_directories)
  [ -n "$artifacts" ] || return 0

  retired=0
  retired_total=0
  while IFS= read -r artifact_dir; do
    [ -n "$artifact_dir" ] || continue
    artifact_is_retired "$artifact_dir" || continue
    case $artifact_dir in
      "$WORKTREE_ROOT"/*/.opencode-artifacts/*) ;;
      *)
        installer_warn "skipping an artifact path outside the worktree root: $artifact_dir"
        continue
        ;;
    esac
    [ ! -L "$artifact_dir" ] || continue
    artifact_bytes=$(directory_bytes "$artifact_dir")
    rm -rf -- "$artifact_dir"
    retired=$((retired + 1))
    retired_total=$((retired_total + artifact_bytes))
  done <<EOF
$artifacts
EOF

  [ "$retired" -eq 0 ] \
    || installer_item "retired $retired delegation artifact directory(ies), $(human_bytes "$retired_total")"
}

repair_log() {
  if [ "$CLEAR_LOGS" -eq 1 ]; then
    cleared=0
    cleared_bytes=0
    for log_path in "$DATA_DIR/log/"*.log "$DATA_DIR/log/"*.log.[0-9]*; do
      [ -f "$log_path" ] && [ ! -L "$log_path" ] || continue
      cleared_bytes=$((cleared_bytes + $(file_bytes "$log_path")))
      rm -- "$log_path"
      cleared=$((cleared + 1))
    done
    installer_item "cleared $cleared log file(s), $(human_bytes "$cleared_bytes")"
    return 0
  fi

  log_bytes=$(file_bytes "$LOG_FILE")
  [ "$log_bytes" -gt "$LOG_ROTATE_BYTES" ] || return 0

  mv -f -- "$LOG_FILE" "$LOG_FILE.1"
  installer_item "rotated $(human_bytes "$log_bytes") of log to $LOG_FILE.1"
}

if [ ! -f "$DATABASE" ]; then
  installer_error "no OpenCode database at $DATABASE"
  installer_hint 'Run OpenCode once, or pass --data-dir for a different data directory.'
  exit 1
fi

MANAGED_ENTRY_NAMES=''
catalog_each_row "$MANAGED_ENTRIES" collect_managed_entry

installer_banner 'inspecting OpenCode runtime state'
report_database
report_log
report_processes
report_workspaces
report_snapshots
report_artifacts
report_configs

if [ "$FIX" -eq 0 ]; then
  installer_success 'OpenCode state reported; rerun with --fix to repair'
  exit 0
fi

require_stopped_opencode
if [ "$CLEAR_LOGS" -eq 1 ] && [ -L "$DATA_DIR/log" ]; then
  installer_error "refusing to clear a symlinked log directory: $DATA_DIR/log"
  exit 1
fi

installer_banner 'repairing OpenCode runtime state'
repair_processes
repair_events
repair_workspaces
repair_snapshots
repair_artifacts
repair_log
installer_success 'OpenCode state repaired'
