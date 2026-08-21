---
description: Run a staged, branch-range, or path-scoped code review
agent: build
---

Delegate to the `reviewer` agent to perform a code review.

**Request:** $ARGUMENTS

Select exactly one review mode:

- No arguments: **staged mode**. Review only the index with `git diff --cached`.
  The calling build orchestrator must supply that diff to the reviewer. This is
  not a three-dot branch/PR review.
- `recent <base-ref>`: **branch mode**. Treat `<base-ref>` as the explicit base
  branch or commit. The calling build orchestrator must calculate
  `merge_base=$(git merge-base <base-ref> HEAD)` and review the fixed-point
  range `git diff "$merge_base" HEAD` (equivalent to `<base-ref>...HEAD`), then
  supply the base ref, merge-base, and complete diff to the shell-less
  reviewer. Never substitute `HEAD~1` or an inferred moving base.
- Any other argument: **path mode**. Review the specified file(s) or directory
  without describing the result as a three-dot branch/PR review.

If `recent` is supplied without `<base-ref>`, stop and ask for the base instead
of guessing one. If the caller cannot inspect Git, stop and request the exact
diff from the build orchestrator rather than asking the reviewer to calculate
it. Pass the selected mode, exact base and merge-base when present, diff, and
file paths to the reviewer.

The reviewer agent will:
- Load the code-review skill
- Apply the 4 Review Layers (Correctness, Security, Performance, Style)
- In branch mode, review the supplied fixed-point three-dot diff from the calculated merge-base.
- In staged and path modes, do not claim a three-dot branch/PR comparison.
- Assess Standards and Spec as independent axes.
- Classify findings by severity (Critical, Major, Minor, Nitpick)
- Only report findings with >=80% confidence
- Include positive observations
- Provide Philosophy Compliance checklist results

Return the complete review findings to the user.
