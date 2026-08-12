---
name: shell-dotfiles
description: Change this macOS Zsh dotfiles repo safely — Brewfile, mise, topics, installers, and documentation tests.
license: MIT
compatibility: opencode
metadata:
  audience: maintainers
  workflow: dotfiles
---

## What I do

- Follow `AGENTS.md` sources of truth (`Brewfile`, `mise/config.toml`, `README.md`)
- Keep topic installers idempotent and non-interactive
- Update README coverage so `tests/documentation_test.sh` stays green
- Prefer fixture tests over commands that mutate the real Mac

## When to use me

Use this when editing packages, runtimes, shell topics, or setup scripts in this repository.
