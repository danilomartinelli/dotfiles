# The doctor reports what it repaired

`opencode/_doctor.sh` has no report phase. Each runtime condition detects once
per run and then either describes what it found, or describes it and repairs
it, so a `--fix` run interleaves the two instead of printing a whole report and
then acting.

## Considered options

The obvious shape is the one that was there: a `report_*` pass over every
condition, then a `repair_*` pass over the ones that can be acted on. It reads
well and it is what a person expects from a tool that is about to delete state.

It is also why six conditions were detected twice per `--fix` run, with
`require_stopped_opencode` in between. The count printed for the replication
log was measured while OpenCode might still have been live; the repair then
measured it again, and nothing reconciled the two. The same gap made
`repair_processes` report `reaped N` from the list it started with rather than
from what was actually gone, which a test then pinned. Two passes over
independently measured state cannot be made honest by discipline: the second
measurement is the bug, and holding the first one means either a findings file
per condition or indirect expansion under `set -u`.

Keeping two phases and skipping the report under `--fix` was the cheaper fix.
It solves the disagreement by removing one of the numbers, and it leaves the
condition split across a detector, a reporter and a repairer that must be kept
in step by hand — which is the shape that let the condition set drift out of
the README, out of `bin/opencode-doctor`, and out of this module's own header.

## Consequences

A `--fix` run reads differently. Each condition is named, described, and acted
on in turn, rather than the whole picture arriving first. Anyone who wants the
picture before anything is touched runs the command without `--fix`, which is
the default and is what the tool recommends.

A refused `--fix` now prints no report at all. Everything that can refuse the
run — a held database, a symlinked log directory — does so before the first
condition is detected, because a report of state that is then left alone is
worse than no report. Running without `--fix` still describes everything.

Adding a condition is a row in `opencode/_runtime-conditions.tsv` and a
`runtime_condition_<name>` function. There is no second list to update, and a
row naming a function nobody wrote stops the run.
