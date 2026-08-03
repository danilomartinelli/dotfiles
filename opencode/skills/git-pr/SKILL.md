---
name: git-pr
description: Draft a focused pull request summary and test plan from the current branch diff against main.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: github
---

## What I do

- Summarize why the branch exists (not a file laundry list)
- Propose a PR title and a short Summary + Test plan body
- Prefer `gh pr create --base main` when the user asks to open the PR

## When to use me

Use this when preparing or opening a GitHub pull request from the current branch.
