# Issue tracker: GitHub

Issues and specs live in GitHub Issues for `danilomartinelli/dotfiles`.
Use the `gh` CLI from this checkout, where `origin` identifies the repository.
Outside the checkout, pass `--repo danilomartinelli/dotfiles` to issue commands.
Write issue titles, bodies, and comments in English.

## Conventions

- **Create**: `gh issue create --title "..." --body-file <body-file>`.
- **Read**: `gh issue view <number> --comments`. For structured data, use
  `gh issue view <number> --json number,title,body,labels,comments,assignees,state`.
- **List**: `gh issue list --state open --json number,title,body,labels,comments,assignees`,
  with appropriate `--label`, `--state`, and `--limit` filters. Paginate when
  the workflow requires every matching issue.
- **Comment**: `gh issue comment <number> --body-file <body-file>`.
- **Apply or remove labels**: `gh issue edit <number> --add-label "..."` or
  `gh issue edit <number> --remove-label "..."`.
- **Close**: `gh issue close <number>`. Post any resolution comment first.

For multiline bodies and comments, write the exact text to a temporary UTF-8
file and pass `--body-file`. Preserve actual newlines and literal shell syntax.
Use the role mapping in `docs/agents/triage-labels.md`.

## Pull requests as a triage surface

**PRs as a request surface: no.**

GitHub shares a number space across issues and pull requests. Resolve an
ambiguous reference before acting; use `gh pr view <number>` and fall back to
`gh issue view <number>`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments` and fetch its labels.

## Wayfinding operations

Used by `/wayfinder`. The map is one issue; its tickets are child issues.

- **Map**: create an issue labelled `wayfinder:map` with the Notes,
  Decisions-so-far, and Fog sections.
- **Child ticket**: link it to the map using GitHub sub-issues. If unavailable,
  add it to a task list in the map and put `Part of #<map>` at the top of its
  body. Apply `wayfinder:research`, `wayfinder:prototype`,
  `wayfinder:grilling`, or `wayfinder:task` according to the ticket type.
- **Blocking**: use native GitHub issue dependencies. Add an edge with
  `gh api --method POST repos/danilomartinelli/dotfiles/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`.
  Get the blocker's database ID with
  `gh api repos/danilomartinelli/dotfiles/issues/<blocker> --jq .id`;
  the issue number and `node_id` are not database IDs. If dependencies are
  unavailable, put `Blocked by: #<number>, #<number>` at the top of the child
  body and resolve the referenced issues' current states.
- **Frontier**: inspect the map's open children in map order. Exclude assigned
  tickets and any with open blockers. Native dependencies expose the open
  blocker count as `issue_dependencies_summary.blocked_by`; for the fallback,
  check every issue in the `Blocked by` line. The first eligible child wins.
- **Claim**: `gh issue edit <number> --add-assignee @me`, as the session's
  first tracker write when resolving a ticket.
- **Resolve**: comment with the answer, close the ticket, then append a link
  to the answer or artifact in the map's Decisions-so-far section.
