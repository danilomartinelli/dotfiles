---
name: code-review
description: Review this worktree and publish actionable findings to the Herdr panel.
disable-model-invocation: true
---

# Code Review

1. Pin the comparison. Use the base the user supplied or the merge base with the local remote-default ref. Include staged, unstaged and relevant untracked source files. If the default ref is unavailable, review local edits against HEAD and state that scope. For an unborn branch, review the pending source files. If a clean checkout has no identifiable comparison, ask for a base in this chat.
1. Review the change against the repository's applicable instructions, coding standards and existing callers. For each regression, give the triggering condition and observable impact. Cite the rule for standards findings. Flag design smells only when they have a concrete cost here.
1. Independently compare the change with the originating issue or spec when available. Cite the requirement for any missing, partial or incorrect behavior. If there is no spec, record that limitation in chat.
1. Publish each distinct actionable finding once. Give a concise comment and one or more repository-relative file paths, with line numbers where useful. Exclude secrets. Leave the checkout untouched.

Write the following JSON shape to the report destination supplied by Herdr. Write a sibling temporary file, then rename it into place so the panel sees the complete report.

```json
{
  "findings": [
    {
      "comment": "Explain the observed behavior, trigger and impact.",
      "paths": ["src/example.ts:42"]
    }
  ]
}
```

Publish an empty findings array when the completed review found nothing. In chat, summarize the scope, findings and checks performed. If publishing failed, report the error there.
