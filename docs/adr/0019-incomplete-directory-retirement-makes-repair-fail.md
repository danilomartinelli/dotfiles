---
status: accepted
---

# Incomplete directory retirement makes repair fail

The doctor counts a directory as retired only after confirming its absence.
Reported byte totals are the sizes measured before removal of fully retired
directories, not a measurement of free disk space; an incomplete removal
contributes neither a directory nor bytes to those totals.

Snapshots, delegation artifacts and agent worktree checkouts share that
retirement contract, including one retry after adjusting write permissions.
Each runtime condition retains its eligibility rules and follow-up cleanup.

A failed retirement names the surviving path and lets independent repairs
continue, but makes the final repair status unsuccessful. Stopping at the first
failure would leave unrelated repairs undone; warning and returning success
would claim a repair that did not finish. Completed retirements remain reported
even when the run fails.
This continuation applies to directory repairs; preflight refusals and fatal
failures in other runtime conditions keep their existing stop behavior.

A failed or incomplete size measurement preserves the target and fails the
repair; a later measurement in the same run cannot override that refusal.
A target already absent contributes no count or bytes and is not an error;
one replaced by a file or symlink is preserved and reported as a failure.
These checks precede removal but do not promise atomic protection against
concurrent replacement.

An ancestor of a failed or refused target is preserved for the rest of that
run, even with `--days 0`. Removing the parent would bypass the child's failed
repair, not constitute an independent repair.

A linked worktree's surviving Git owner must be identified before removal;
failure to identify it preserves the checkout and fails the repair. Once the
checkout is gone, a failed registration cleanup does not undo its retirement
count or bytes, but the repair fails and names the owner still needing
maintenance. Ordinary clones have no external worktree registration to clean.
Removing a snapshot's empty parent remains optional.

Recovery after an incomplete removal or failed Git registration cleanup is
manual when the next run can no longer identify the target. Diagnostics name
the affected path, the failed step and the Git owner when known; they do not
promise that rerunning the doctor will finish the repair. A partial removal
can erase the metadata needed to establish eligibility, and a removed checkout
cannot supply its owner on the next run.

No retirement journal or ancestor protection persists between runs. A new run
reapplies the existing eligibility rules, including the retention window;
`--days 0` bypasses age only. Automatic recovery across runs would require
durable state and is outside this change.
