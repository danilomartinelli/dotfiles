#!/bin/sh
#
# Report and repair the OpenCode runtime state that nothing else owns.
#
# install.sh links the tracked half of OpenCode into ~/.config/opencode. The
# other half is the data directory, and OpenCode prunes none of it. What
# accumulates there is declared in _runtime-conditions.tsv, one row per
# condition, and the README table is rendered from that catalog: the list used
# to be restated in this header, in the report order, in the repair order, in
# bin/opencode-doctor and in the README, and four of those five had drifted.
#
# Each row binds to a runtime_condition_<name> function below, which detects
# its condition once per run and then reports it, or reports and repairs it.
# Detecting once is what makes the numbers honest — a report and a repair that
# each measured separately, on opposite sides of the idle check, could disagree
# about what was there.
# docs/adr/0015-the-doctor-reports-what-it-repaired.md
#
# Reporting is the default because every repair deletes state no backup covers.
# Repairs need --fix and refuse to run while OpenCode holds the database. That
# one precondition is also what makes reaping safe to state: a process still
# living inside an agent worktree while no OpenCode runs has no owner left to
# lose, so no ancestry heuristic has to decide it.
#
# Snapshots, delegation artifacts and agent worktree checkouts leave through one
# operation, retire_directory. Each condition keeps the question of which
# directories may go and what to tidy once they have; the operation owns what
# "retired" means. A directory counts only once it is confirmed gone, its bytes
# are what it measured before removal, and one that survives, or that could not
# be measured or identified, keeps the repair from ending in success without
# stopping the repairs that do not depend on it.
# docs/adr/0019-incomplete-directory-retirement-makes-repair-fail.md
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

# shellcheck source=opencode/_runtime-store.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/_runtime-store.sh"

MANAGED_ENTRIES=$SCRIPT_DIR/_managed-entries.tsv
RUNTIME_CONDITIONS=$SCRIPT_DIR/_runtime-conditions.tsv

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

LOG_FILE=$DATA_DIR/log/opencode.log
WORKTREE_ROOT=$DATA_DIR/worktree
SNAPSHOT_ROOT=$DATA_DIR/snapshot

require_command() {
  command -v "$1" >/dev/null 2>&1 && return 0
  installer_error "$1 is required to inspect the OpenCode data directory"
  installer_hint "$2"
  exit 1
}

require_command sqlite3 'It ships with macOS; check PATH before rerunning.'
require_command lsof 'It ships with macOS; check PATH before rerunning.'
require_command git 'Install the Command Line Tools, then rerun.'

file_bytes() {
  [ -f "$1" ] || {
    printf '0\n'
    return 0
  }
  wc -c <"$1" | tr -d ' '
}

TAB=$(printf '\t')

# Whether <path> is one of the lines of <list>.
path_listed() {
  case "
$2" in
    *"
$1
"*) return 0 ;;
  esac
  return 1
}

# The allocated size of a directory, in bytes, into MEASURED_BYTES.
#
# A size is only a size when du finished without complaint and printed one. du
# still prints a total after failing to read part of a tree, and an empty or
# garbled answer read as arithmetic is zero; both used to reach the totals as if
# they were measurements. A failure is remembered for the rest of the run, so a
# directory that could not be measured is never retired on the strength of
# a later attempt that happened to succeed.
MEASUREMENT_REFUSED=''

measure_directory() {
  MEASURED_BYTES=0
  if path_listed "$1" "$MEASUREMENT_REFUSED"; then
    return 1
  fi

  measured=$(du -sk -- "$1" 2>/dev/null) || measured=''
  case $measured in
    [0-9]*"$TAB"*) measured=${measured%%"$TAB"*} ;;
    *) measured='' ;;
  esac
  case $measured in
    '' | *[!0-9]*)
      MEASUREMENT_REFUSED="$MEASUREMENT_REFUSED$1
"
      return 1
      ;;
  esac

  MEASURED_BYTES=$((measured * 1024))
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

# A workspace row whose directory is gone describes nothing a session can be
# resumed into, and it is the shape the rows with a retired adapter took.
stale_workspaces() {
  runtime_store_workspace_rows \
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

# What this run could not retire. A directory whose repair failed or was
# refused is kept, and so is every directory above it: removing the parent
# would carry out the very removal that was just refused, whatever the
# retention window says. None of it outlives the run.
RETIREMENT_UNRESOLVED=''
RETIREMENT_FAILURES=0
REGISTRATION_FAILURES=0

# Record a directory repair that did not finish and say what is left of it.
# Usage: record_unretired <path> <what went wrong> <what to do about it>
record_unretired() {
  RETIREMENT_UNRESOLVED="$RETIREMENT_UNRESOLVED$1
"
  RETIREMENT_FAILURES=$((RETIREMENT_FAILURES + 1))
  installer_warn "could not retire $1: $2"
  installer_hint "$3"
}

# A path below <path> whose repair did not finish in this run, into
# RETIREMENT_BLOCKER. Ancestry is matched a whole component at a time, so a
# failure inside .../pushed-copy says nothing about .../pushed.
retirement_blocker() {
  while IFS= read -r unresolved; do
    case $unresolved in
      "$1"/*)
        RETIREMENT_BLOCKER=$unresolved
        return 0
        ;;
    esac
  done <<EOF
$RETIREMENT_UNRESOLVED
EOF
  return 1
}

# Retire one directory a condition has selected: measure it, remove it, retry
# once with write permission restored, and confirm it is gone. Which
# directories may go, and whatever tidying follows, stays with the condition;
# what "retired" means lives here, so the three conditions that remove
# directories cannot each mean something different by it.
#
# Returns 0 when the directory was there and is now confirmed gone, with its
# pre-removal size in RETIRED_BYTES; 1 when it is kept, which is reported and
# fails the repair; 2 when it was gone before anything acted, which is neither
# a retirement nor a failure.
#
# An optional <admit> function runs once the target is known to be a real
# directory and before anything destructive. It returns non-zero to keep the
# directory, setting RETIREMENT_REFUSAL and RETIREMENT_REFUSAL_HINT, and may set
# RETIREMENT_NOTE for any diagnostic about the removal that follows.
#
# A build cache is not made only of files this user can delete: a downloader
# that caches a signed application bundle writes it back read-only, and the
# first rm -rf leaves the whole subtree standing. The retry exists for that
# case. The final test exists because an exit status is not proof -- both
# attempts can still leave the directory on a mount that went away, or on a
# path something else has open. The byte counts used to be added up before the
# removal and printed whether or not it worked, so a run that could not delete
# 42 GB still said it had.
#
# Usage: retire_directory <path> [<admit>]
retire_directory() {
  retiring=$1
  RETIRED_BYTES=0
  RETIREMENT_NOTE=''

  # A dangling symlink is not absence.
  if [ ! -e "$retiring" ] && [ ! -L "$retiring" ]; then
    return 2
  fi
  # Deciding that a directory may go does not authorize deleting whatever has
  # taken its place, and nothing here follows a link.
  if [ -L "$retiring" ] || [ ! -d "$retiring" ]; then
    record_unretired "$retiring" 'it is no longer a directory' \
      'Nothing was removed or followed; inspect what replaced it by hand.'
    return 1
  fi
  if retirement_blocker "$retiring"; then
    record_unretired "$retiring" "$RETIREMENT_BLOCKER inside it was not retired" \
      'It is kept for the rest of this run; see what was reported for the path inside it.'
    return 1
  fi
  if [ "$#" -gt 1 ] && ! "$2" "$retiring"; then
    record_unretired "$retiring" "$RETIREMENT_REFUSAL" "$RETIREMENT_REFUSAL_HINT"
    return 1
  fi
  if ! measure_directory "$retiring"; then
    record_unretired "$retiring" 'its size could not be measured' \
      "Nothing was removed.${RETIREMENT_NOTE:+ $RETIREMENT_NOTE} Check that everything inside it is readable, then inspect it by hand."
    return 1
  fi

  survival='it survived removal'
  rm -rf -- "$retiring" 2>/dev/null || true
  if [ -e "$retiring" ] || [ -L "$retiring" ]; then
    chmod -R u+w -- "$retiring" 2>/dev/null \
      || survival='it survived removal, and its write permission could not be restored'
    rm -rf -- "$retiring" 2>/dev/null || true
  fi
  if [ -e "$retiring" ] || [ -L "$retiring" ]; then
    record_unretired "$retiring" "$survival" \
      "Part of it may already be gone, including what a later run would need to recognize it.${RETIREMENT_NOTE:+ $RETIREMENT_NOTE} Inspect and recover it by hand."
    return 1
  fi

  RETIRED_BYTES=$MEASURED_BYTES
}

# Every checkout below the worktree root. The doctor owned everything inside
# one -- the processes, the snapshots, the artifacts -- and never the checkout
# itself, so a retired session left its node_modules and build output behind
# permanently.
#
# Which of them may go is decided in runtime_condition_worktrees, from
# worktree_state and worktree_is_idle. Processes are not consulted here: the
# processes condition runs first in the catalog and has already reaped anything
# living inside one by the time this is asked.
#
# The depth is the one artifact_directories already assumes: a worktree root
# holds one directory per checkout.
worktree_checkouts() {
  [ -d "$WORKTREE_ROOT" ] || return 0
  find "$WORKTREE_ROOT" -mindepth 2 -maxdepth 2 -type d 2>/dev/null
}

# What a checkout is: reconstructible, holding work, or not judgeable here.
#
# Reconstructible means every byte in it exists somewhere else -- no
# uncommitted change, nothing untracked that Git would report, and no commit
# an upstream does not already have. Only such a directory may be retired.
#
# Holding work is the opposite, and a retention window has no standing to
# discard it. A directory that is not a Git checkout, or one whose branch
# tracks nothing, is neither: this module cannot tell a scratch directory from
# something deliberate, so it says so and leaves it, the way stale_snapshots
# leaves a snapshot whose config names no worktree.
WORKTREE_RECONSTRUCTIBLE=0
WORKTREE_HOLDS_WORK=1
WORKTREE_UNJUDGEABLE=2

# Git, in the checkout this condition is asking about. It is a function rather
# than a command held in a variable because the checkout path is one of the
# arguments: an unquoted expansion would split a path containing a space into
# two of them.
#
# --no-optional-locks because a plain `git status` refreshes the index and
# writes it back. Asking the question would then be what made the answer to
# worktree_is_idle wrong: the checkout looked written-to a moment ago, every
# time, so no checkout was ever idle and the condition retired nothing.
worktree_git() {
  _worktree_checkout=$1
  shift
  git -C "$_worktree_checkout" --no-optional-locks -c core.fsmonitor=false "$@"
}

worktree_state() {
  worktree_git "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || return "$WORKTREE_UNJUDGEABLE"
  [ -z "$(worktree_git "$1" status --porcelain --untracked-files=normal 2>/dev/null)" ] \
    || return "$WORKTREE_HOLDS_WORK"
  worktree_git "$1" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 \
    || return "$WORKTREE_UNJUDGEABLE"
  [ -z "$(worktree_git "$1" log --oneline '@{u}..HEAD' 2>/dev/null)" ] \
    || return "$WORKTREE_HOLDS_WORK"
  return "$WORKTREE_RECONSTRUCTIBLE"
}

# Nothing has written source here inside the window. `.git` is excluded on
# purpose: Git rewrites its own bookkeeping whenever anything reads the
# repository, including this module, so those timestamps answer "was this
# checkout inspected" and never "is an agent still working in it".
#
# `.opencode-artifacts` is deliberately NOT excluded. The artifacts condition
# runs first and, having just retired a directory inside it, leaves the
# artifact root looking written-to, so a checkout whose artifacts went in this
# run is retired by the next one instead. That is the conservative order:
# recent artifacts are the evidence that a delegation recently worked here, and
# a window that retires the checkout anyway would be deciding on the strength
# of a timestamp this module had itself just moved. A zero-day window is
# unaffected -- it retires everything without consulting an mtime at all.
worktree_is_idle() {
  if [ "$RETENTION_DAYS" -eq 0 ]; then
    return 0
  fi
  [ -z "$(find "$1" -name .git -prune -o -mtime -"$RETENTION_DAYS" -print -quit 2>/dev/null)" ]
}

# Who else holds a record of this checkout, asked while it still exists.
#
# A linked worktree is registered in the repository it was added from, and the
# only thing naming that repository is the checkout's own .git file, which
# leaves with the checkout. So the owner is established before removal, and a
# linked checkout whose owner cannot be established is kept rather than
# retired into a registration nobody can find again. An ordinary clone carries
# its repository inside it and leaves nothing behind to clean.
#
# This is retire_directory's <admit> for checkouts. It runs only once the
# checkout is known to exist, so one that vanished first is not mistaken for
# one whose owner could not be found.
identify_checkout_owner() {
  CHECKOUT_OWNER=''
  CHECKOUT_REGISTRATION=''
  RETIREMENT_REFUSAL='its Git owner could not be identified'
  RETIREMENT_REFUSAL_HINT='Nothing was removed. Inspect the checkout and the repository it was created from by hand.'

  identity=$(worktree_git "$1" rev-parse --path-format=absolute \
    --git-dir --git-common-dir 2>/dev/null </dev/null) || return 1
  identity_git_dir=$(printf '%s\n' "$identity" | sed -n 1p)
  identity_common_dir=$(printf '%s\n' "$identity" | sed -n 2p)
  if [ -z "$identity_git_dir" ] || [ -z "$identity_common_dir" ]; then
    return 1
  fi

  [ "$identity_git_dir" != "$identity_common_dir" ] || return 0

  RETIREMENT_REFUSAL="its Git owner $identity_common_dir could not be verified"
  case $identity_common_dir in
    "$1" | "$1"/*) return 1 ;;
  esac
  case $identity_git_dir in
    "$identity_common_dir"/worktrees/*) ;;
    *) return 1 ;;
  esac
  if [ ! -d "$identity_common_dir" ] || [ ! -d "$identity_git_dir" ]; then
    return 1
  fi

  CHECKOUT_OWNER=$identity_common_dir
  CHECKOUT_REGISTRATION=$identity_git_dir
  RETIREMENT_NOTE="Its Git owner is $CHECKOUT_OWNER."
}

# The maintenance a retired linked worktree owes its owner: dropping the one
# registration that described it. `git worktree prune` would also drop the
# registration of any other worktree that merely cannot be reached right now,
# such as one on a volume that is not mounted. The directory is already gone
# and stays counted; a registration left behind is its own failure, reported
# with the owner while this run still knows it.
remove_checkout_registration() {
  if git --git-dir "$CHECKOUT_OWNER" -c core.fsmonitor=false \
    worktree remove "$1" >/dev/null 2>&1 </dev/null \
    && [ ! -e "$CHECKOUT_REGISTRATION" ]; then
    return 0
  fi

  REGISTRATION_FAILURES=$((REGISTRATION_FAILURES + 1))
  installer_warn "retired $1, but could not remove its Git registration from $CHECKOUT_OWNER"
  installer_hint "Inspect it with git --git-dir '$CHECKOUT_OWNER' worktree list and remove it by hand; a later run cannot find this owner, because the checkout that named it is gone."
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

# Each condition detects once, then says what it found and — in repair mode —
# what it did about it.

runtime_condition_processes() {
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
  [ "$1" = repair ] || return 0

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

  # What is gone, not what was signalled. A process that exited on its own, or
  # that survived the kill, was counted as reaped when this reported the list
  # it started from.
  remaining=$(leaked_processes)
  installer_item "reaped $(($(line_count "$leaked") - $(line_count "$remaining"))) process(es) left inside an agent worktree"
  [ -z "$remaining" ] \
    || installer_warn "$(line_count "$remaining") process(es) are still inside an agent worktree"
}

runtime_condition_events() {
  prunable=$(runtime_store_prunable_event_count)
  installer_note "prunable replication events (finished sessions, or idle for $RETENTION_DAYS days): $prunable"
  [ "$1" = repair ] || return 0

  if [ "$prunable" -eq 0 ]; then
    installer_note 'no prunable replication events'
    return 0
  fi

  before=$(file_bytes "$(runtime_store_path)")
  runtime_store_prune_events
  after=$(file_bytes "$(runtime_store_path)")

  installer_item "pruned replication events of finished sessions and of sessions idle for $RETENTION_DAYS days"
  installer_item "database $(human_bytes "$before") to $(human_bytes "$after")"
}

runtime_condition_workspaces() {
  unreadable=$(runtime_store_unreadable_workspaces)
  [ "$unreadable" -eq 0 ] \
    || installer_warn "$unreadable workspace row(s) name a directory containing a newline and are not inspected"

  stale=$(stale_workspaces)
  if [ -z "$stale" ]; then
    installer_note 'no workspace rows describe a missing directory'
    return 0
  fi

  printf '%s\n' "$stale" | while IFS="$(printf '\t')" read -r workspace_id workspace_type workspace_directory; do
    [ -n "$workspace_id" ] || continue
    installer_note "workspace $workspace_id ($workspace_type) lost $workspace_directory"
  done
  [ "$1" = repair ] || return 0

  removed=0
  while IFS="$(printf '\t')" read -r workspace_id workspace_type workspace_directory; do
    [ -n "$workspace_id" ] || continue
    if runtime_store_delete_workspace "$workspace_id"; then
      removed=$((removed + 1))
    fi
  done <<EOF
$stale
EOF

  [ "$removed" -eq 0 ] || installer_item "removed $removed workspace row(s) describing a missing directory"
}

runtime_condition_sessions() {
  dangling=$(runtime_store_dangling_session_count)
  if [ "$dangling" -eq 0 ]; then
    installer_note 'no sessions point at a workspace that is gone'
    return 0
  fi

  installer_note "sessions that cannot be deleted or archived, their workspace row gone: $dangling"
  [ "$1" = repair ] || return 0

  runtime_store_release_dangling_sessions
  installer_item "released $dangling session(s) whose workspace row was gone"
}

# A snapshot whose directory is gone can never be restored into, so it goes
# whole rather than by retention. The hash directory above it is removed only
# when the last snapshot under it leaves, and only as tidying: keeping it takes
# nothing back from the snapshot already retired.
runtime_condition_snapshots() {
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
  [ "$1" = repair ] || return 0

  removed=0
  removed_bytes=0
  while IFS="$(printf '\t')" read -r snapshot_dir snapshot_worktree; do
    [ -n "$snapshot_dir" ] || continue
    case $snapshot_dir in
      "$SNAPSHOT_ROOT"/*) ;;
      *)
        record_unretired "$snapshot_dir" 'it lies outside the snapshot root' \
          'Nothing was removed. This condition only cleans below its own root; inspect how the path was selected by hand.'
        continue
        ;;
    esac
    retire_directory "$snapshot_dir" || continue
    removed=$((removed + 1))
    removed_bytes=$((removed_bytes + RETIRED_BYTES))
    rmdir -- "$(dirname -- "$snapshot_dir")" 2>/dev/null || true
  done <<EOF
$snapshots
EOF

  [ "$removed" -eq 0 ] \
    || installer_item "removed $removed session snapshot(s) describing a missing directory, $(human_bytes "$removed_bytes")"
}

# Retiring a directory takes its evidence with it, which is the whole point of
# requiring --fix. The path guard is against a malformed list rather than a
# depth proof: everything here came from a search rooted in the data directory.
runtime_condition_artifacts() {
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
    artifact_bytes=0
    if measure_directory "$artifact_dir"; then
      artifact_bytes=$MEASURED_BYTES
    else
      installer_warn "could not measure $artifact_dir; its size is left out of the reported total"
    fi
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
  [ "$1" = repair ] || return 0

  retired=0
  retired_bytes=0
  while IFS= read -r artifact_dir; do
    [ -n "$artifact_dir" ] || continue
    artifact_is_retired "$artifact_dir" || continue
    case $artifact_dir in
      "$WORKTREE_ROOT"/*/.opencode-artifacts/*) ;;
      *)
        record_unretired "$artifact_dir" 'it lies outside the worktree root' \
          'Nothing was removed. This condition only cleans below its own root; inspect how the path was selected by hand.'
        continue
        ;;
    esac
    retire_directory "$artifact_dir" || continue
    retired=$((retired + 1))
    retired_bytes=$((retired_bytes + RETIRED_BYTES))
  done <<EOF
$artifacts
EOF

  [ "$retired" -eq 0 ] \
    || installer_item "retired $retired delegation artifact directory(ies), $(human_bytes "$retired_bytes")"
}

# The checkout an agent worktree is made of. Retiring one takes its build
# output with it, which is the point: a worktree is reconstructed from the
# repository it links to, and nothing here is a source of truth. A checkout
# holding uncommitted, untracked or unpushed work is named and left alone,
# because a retention window is not standing to discard work that exists
# nowhere else.
#
# Git keeps a registration for a linked worktree in the repository it belongs
# to. Removing the directory alone leaves that registration behind, so the
# owner is identified before the checkout goes and its registration is removed
# right after; see identify_checkout_owner and remove_checkout_registration.
runtime_condition_worktrees() {
  checkouts=$(worktree_checkouts)
  if [ -z "$checkouts" ]; then
    installer_note 'no agent worktree checkouts'
    return 0
  fi

  checkout_total=0
  idle=''
  held=''
  unjudged=0
  while IFS= read -r checkout; do
    [ -n "$checkout" ] || continue
    if measure_directory "$checkout"; then
      checkout_total=$((checkout_total + MEASURED_BYTES))
    else
      installer_warn "could not measure $checkout; its size is left out of the reported total"
    fi
    checkout_state=0
    worktree_state "$checkout" || checkout_state=$?
    case $checkout_state in
      "$WORKTREE_HOLDS_WORK")
        held="$held$checkout
"
        continue
        ;;
      "$WORKTREE_UNJUDGEABLE")
        unjudged=$((unjudged + 1))
        continue
        ;;
    esac
    worktree_is_idle "$checkout" || continue
    idle="$idle$checkout
"
  done <<EOF
$checkouts
EOF

  # line_count answers about a list with no trailing newline, which is what a
  # command substitution hands it. These two were built a line at a time, so
  # they carry one, and counting one directly reported one entry too many.
  held=$(printf '%s' "$held")
  idle=$(printf '%s' "$idle")

  installer_note "agent worktree checkouts: $(line_count "$checkouts"), $(human_bytes "$checkout_total")"
  [ "$unjudged" -eq 0 ] \
    || installer_note "checkouts nothing here can judge, and so keeps: $unjudged"
  # The newline stripped above is put back for the read loop, which drops a
  # final line that has no terminator.
  printf '%s\n' "$held" | while IFS= read -r checkout; do
    [ -n "$checkout" ] || continue
    installer_warn "worktree holds work that is not on a remote: $checkout"
    installer_hint 'Push or discard it there, then rerun to retire the checkout.'
  done
  installer_note "retired checkouts (idle for $RETENTION_DAYS days): $(line_count "$idle")"
  [ "$1" = repair ] || return 0

  retired=0
  retired_bytes=0
  while IFS= read -r checkout; do
    [ -n "$checkout" ] || continue
    case $checkout in
      "$WORKTREE_ROOT"/*/*) ;;
      *)
        record_unretired "$checkout" 'it lies outside the worktree root' \
          'Nothing was removed. This condition only cleans below its own root; inspect how the path was selected by hand.'
        continue
        ;;
    esac
    CHECKOUT_OWNER=''
    retire_directory "$checkout" identify_checkout_owner || continue
    retired=$((retired + 1))
    retired_bytes=$((retired_bytes + RETIRED_BYTES))
    [ -z "$CHECKOUT_OWNER" ] || remove_checkout_registration "$checkout"
  done <<EOF
$idle
EOF

  [ "$retired" -eq 0 ] \
    || installer_item "retired $retired agent worktree checkout(s), $(human_bytes "$retired_bytes")"
}

runtime_condition_configs() {
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

runtime_condition_log() {
  log_bytes=$(file_bytes "$LOG_FILE")
  installer_note "log $(human_bytes "$log_bytes") at $LOG_FILE"
  [ "$1" = repair ] || return 0

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

  [ "$log_bytes" -gt "$LOG_ROTATE_BYTES" ] || return 0

  mv -f -- "$LOG_FILE" "$LOG_FILE.1"
  installer_item "rotated $(human_bytes "$log_bytes") of log to $LOG_FILE.1"
}

require_stopped_opencode() {
  holders=$(runtime_store_holders)
  [ -n "$holders" ] || return 0

  installer_error 'OpenCode is running and holds the database'
  installer_hint "Quit the OpenCode desktop app and any opencode session, then rerun. Holding pids: $(printf '%s' "$holders" | tr '\n' ' ')"
  exit 1
}

# The catalog's declaration decides both what runs and whether it may act, so a
# row naming a condition nobody implemented stops the run instead of being
# quietly skipped.
run_condition() {
  condition_name=$1
  condition_action=$3

  command -v "runtime_condition_$condition_name" >/dev/null 2>&1 || {
    installer_error "the runtime conditions catalog names an unknown condition: $condition_name"
    exit 1
  }

  if [ "$FIX" -eq 1 ] && [ "$condition_action" = repair ]; then
    "runtime_condition_$condition_name" repair
  else
    "runtime_condition_$condition_name" report
  fi
  return 0
}

runtime_store_open "$DATA_DIR" "$RETENTION_DAYS"

MANAGED_ENTRY_NAMES=''
catalog_each_row "$MANAGED_ENTRIES" collect_managed_entry

# Everything that can refuse the run does so before any condition is detected,
# so a refused --fix never prints half a picture of state it then leaves alone.
if [ "$FIX" -eq 1 ]; then
  require_stopped_opencode
  if [ "$CLEAR_LOGS" -eq 1 ] && [ -L "$DATA_DIR/log" ]; then
    installer_error "refusing to clear a symlinked log directory: $DATA_DIR/log"
    exit 1
  fi
  runtime_store_permit_writes
  installer_banner 'inspecting and repairing OpenCode runtime state'
else
  installer_banner 'inspecting OpenCode runtime state'
fi

installer_note "database $(human_bytes "$(file_bytes "$(runtime_store_path)")") at $(runtime_store_path)"
catalog_each_row "$RUNTIME_CONDITIONS" run_condition

if [ "$FIX" -eq 0 ]; then
  installer_success 'OpenCode state reported; rerun with --fix to repair'
  exit 0
fi

# A directory repair that did not finish lets every independent one go ahead,
# and then keeps the run from calling itself repaired. What did finish was
# reported where it happened, so nothing here needs to repeat it.
if [ "$RETIREMENT_FAILURES" -gt 0 ] || [ "$REGISTRATION_FAILURES" -gt 0 ]; then
  installer_error "OpenCode repair incomplete: $RETIREMENT_FAILURES directory(ies) not retired, $REGISTRATION_FAILURES Git registration(s) left behind"
  installer_hint 'Every step reported as done above is done. Inspect each path named above by hand: a later run judges eligibility afresh and does not resume this one.'
  exit 1
fi

installer_success 'OpenCode state repaired'
