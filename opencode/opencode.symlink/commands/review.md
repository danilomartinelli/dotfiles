---
description: Run a staged, branch-range, or path-scoped code review
---

Delegate to the `reviewer` agent to perform a code review.

**Request:** $ARGUMENTS

Select exactly one review mode:

- No arguments: **staged mode**. Review only the index with `git diff --cached`.
  This is not a three-dot branch/PR review.
- `recent <base-ref>`: **branch mode**. Treat `<base-ref>` as the explicit base
  branch or commit. The reviewer must calculate
  `merge_base=$(git merge-base <base-ref> HEAD)` and review the fixed-point
  range `git diff "$merge_base" HEAD` (equivalent to `<base-ref>...HEAD`).
  Never substitute `HEAD~1` or an inferred moving base.
- Any other argument: **path mode**. Review the specified file(s) or directory
  without describing the result as a three-dot branch/PR review.

If `recent` is supplied without `<base-ref>`, stop and ask for the base instead
of guessing one. Pass the selected mode and exact base (when present) to the
reviewer.

The reviewer agent will:
- Load the code-review skill
- Apply the 4 Review Layers (Correctness, Security, Performance, Style)
- In branch mode, review the fixed-point three-dot diff from the calculated merge-base.
- In staged and path modes, do not claim a three-dot branch/PR comparison.
- Assess Standards and Spec as independent axes.
- Classify findings by severity (Critical, Major, Minor, Nitpick)
- Only report findings with >=80% confidence
- Include positive observations
- Provide Philosophy Compliance checklist results

Return the complete review findings to the user.
