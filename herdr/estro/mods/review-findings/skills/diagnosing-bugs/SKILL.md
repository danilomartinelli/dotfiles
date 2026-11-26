---
name: diagnosing-bugs
description: Verify and fix the review findings selected in Herdr.
disable-model-invocation: true
---

# Diagnosing Bugs

1. Treat the selected comments and paths as review evidence. Inspect the current checkout, applicable repository instructions and referenced callers. Record which findings still apply.
1. For each behavioral defect, establish a focused pass/fail signal using a local fixture or an existing test. State what observation would distinguish the likely causes. Run the check and narrow the cause using that evidence. For a standards finding, verify the cited rule against the current source.
1. Fix the confirmed cause in the owning source. Preserve unrelated work. Run the focused check again and the relevant repository checks. Remove temporary instrumentation, preserving meaningful regression coverage.
1. Account for every selected finding in chat. Give the changed paths and verification result for each fix. For a stale or unconfirmed finding, explain the evidence or the missing input. Keep changes in the worktree for the user to inspect.
