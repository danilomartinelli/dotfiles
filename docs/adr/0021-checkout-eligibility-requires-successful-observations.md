---
status: accepted
---

# Checkout eligibility requires successful observations

An observation that fails cannot establish checkout eligibility. The doctor
preserves the affected checkout, names its path and the failed step, and
continues independent assessments and repairs. Both report and repair finish
with exit status 1 when an assessment failed; preserving a checkout does not
make an incomplete assessment successful. A detached HEAD or a branch without
an upstream remains an ordinary reason to preserve a checkout, not an
operational failure. The same applies when a configured upstream ref is gone
after pruning a deleted remote branch. A failed ref lookup remains an
operational failure; only confirmed absence is ordinary preservation.

One assessment owns the Git observations, inactivity check and eligibility
decision for each checkout, including the owner required for a linked
worktree. Its result distinguishes eligible, preserved and failed, with a
reason; the runtime condition consumes that result rather than combining
separate predicates. Assessment neither prints nor removes anything. It stays
in `_doctor.sh` initially; a separate file or generic process abstraction is
not required. Presentation and Directory retirement retain their existing
owners.

Discovery must finish successfully before any checkout can be selected. If
listing the checkout directories fails, all checkouts are preserved for that
condition, even if the command produced a partial list. The doctor reports the
failed discovery and finishes with status 1 in report and repair modes, while
other independent conditions continue. A partial list is not evidence of a
complete inventory or an empty root.

Assessment remains offline and uses the locally recorded upstream history.
Checking the remote would introduce network and authentication requirements
into local maintenance, so eligibility makes no claim about changes to that
history since its last local observation. Files ignored by Git do not prevent
retirement, including local configuration files as well as build output.
Calling an eligible checkout "reconstructible" would promise more than these
observations establish.

Only linked worktrees whose external Git owner has been identified and will
be preserved may become eligible. Independent clones are kept with an explicit
reason and do not make the run fail. A clone's clean checkout and published
HEAD do not establish that its other branches or stash have another copy;
retiring it also removes the Git repository that holds them. Preserving clones
keeps that work without expanding the doctor into an audit of every Git
reference. This narrows the previous eligibility policy, which allowed clones.

This decision concerns selection before Directory retirement. It preserves
the independent-repair continuation and confirmed-removal accounting in
[ADR-0019](0019-incomplete-directory-retirement-makes-repair-fail.md), and the
condition-by-condition execution in
[ADR-0015](0015-the-doctor-reports-what-it-repaired.md).

Existing retention and removal safeguards continue to apply. `--days 0`
bypasses age only; it cannot override failed observations or ordinary reasons
for preservation. The stopped-OpenCode preflight remains required for repair.
An assessment is made once per checkout, without promising atomic protection
against concurrent external changes; the existing removal-time safeguards
still check the target before acting.

The accepted contract is implemented in `opencode/_doctor.sh` and exercised
through the doctor CLI with isolated fixtures.
