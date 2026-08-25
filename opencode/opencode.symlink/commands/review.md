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
- `pr <number-or-url>`: **pull-request mode**. Resolve the PR with authenticated
  read-only `gh` commands. Retrieve its metadata, checks, issue comments,
  review submissions, and inline review comments. When the request starts from
  a commit or pasted comment, first map the commit to its owning PR with the
  REST commit-pulls endpoint instead of trusting a stale PR number. Calculate
  the local merge-base from the PR's explicit base ref, collect the complete
  diff, and supply both local and remote evidence to the reviewer. `gh api` is
  GET-only; never add fields or an input body, use GraphQL, or chain it with
  another shell command. Use the REST routes
  `repos/{owner}/{repo}/commits/<sha>/pulls`,
  `repos/{owner}/{repo}/issues/<number>/comments`,
  `repos/{owner}/{repo}/pulls/<number>/reviews`, and
  `repos/{owner}/{repo}/pulls/<number>/comments` as applicable, with
  `--paginate` for collection endpoints.
- Any other argument: **path mode**. Review the specified file(s) or directory
  without describing the result as a three-dot branch/PR review.

If `recent` is supplied without `<base-ref>`, stop and ask for the base instead
of guessing one. If the caller cannot inspect Git, stop and request the exact
diff from the build orchestrator rather than asking the reviewer to calculate
it. Pass the selected mode, exact base and merge-base when present, diff, and
file paths to the reviewer.

The reviewer agent receives all local and remote evidence from build; it never
uses credentials or fetches a private repository itself. It will:
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
