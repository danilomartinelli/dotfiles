# Triage labels

Map each canonical triage role to the existing GitHub label below.

| Canonical role    | GitHub label      | Meaning                                            |
| ----------------- | ----------------- | -------------------------------------------------- |
| `needs-triage`    | `needs-triage`    | Danilo needs to evaluate the issue                 |
| `needs-info`      | `needs-info`      | Waiting for more information from the reporter     |
| `ready-for-agent` | `ready-for-agent` | Fully specified and ready for agent implementation |
| `ready-for-human` | `ready-for-human` | Requires human implementation                      |
| `wontfix`         | `wontfix`         | Will not be actioned                               |

When a skill names a triage role, use the corresponding GitHub label.
Edit the GitHub label column if the repository's vocabulary changes.

The bug and enhancement forms apply `needs-triage` alongside their type label
(`bug` or `enhancement`). Filling out a form does not make an issue
`ready-for-agent`; Danilo evaluates it first.

Blank issues remain available for specs and Wayfinder maps and tickets. Issues
created without a form need their labels assigned explicitly; use the
conventions in [Issue tracker](issue-tracker.md).
