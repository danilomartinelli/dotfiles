---
name: add-topic
description: Add a new top-level topic/config folder to this dotfiles repo with the standard files (install.sh, path/env/aliases, symlink, README coverage).
license: MIT
compatibility: opencode
metadata:
  audience: maintainers
  workflow: dotfiles
---

## What I do

Scaffold a new visible topic under the repository root and wire it into Brewfile,
README, and tests when needed.

## Layout to create

```text
topic-name/
├── install.sh       # optional; must be executable; idempotent; non-interactive
├── path.zsh         # optional; PATH only; loaded first
├── env.zsh          # optional; exports
├── aliases.zsh      # optional; aliases (also counted as main config)
├── completion.zsh   # optional; after compinit
├── *.zsh            # optional; other main shell config
└── *.symlink        # optional; linked to ~/.<basename> by bootstrap
```

For configs that live under `~/.config/<tool>/` (Ghostty/Zed/AeroSpace style),
keep the tracked files in the topic and have `install.sh` create the destination
directory, then call `_scripts/link-config` (default policy `replace-with-backup`).
Use `--policy preserve-existing` when local machine tweaks must win, or
`--policy numbered-backup` when collisions need free `.backup.N` suffixes (SSH).
Do not reimplement link/backup logic inside the installer.

## Rules

1. Topic directory name must not start with `_` and must not be `bin`,
   `functions`, or `tests`.
2. `install.sh` must use `set -e` (or `set -eu`), skip non-Darwin when
   macOS-only, and be safe to run from both bootstrap and `dot`.
3. Do not generate credentials in installers. Use an explicit `bin/*-create`
   adapter when key material is needed (see SSH/SOPS).
4. If the topic adds Homebrew packages, update `Brewfile`.
5. If the topic adds runtimes/tools, update `mise/mise.toml.symlink`.
6. Update `README.md` for every new public `bin/` command, alias, Brewfile
   package, and Mise tool — `tests/documentation_test.sh` enforces this.
7. Prefer fixture tests over mutating the real Mac.
8. Keep secrets out of the topic; document env vars in `.localrc.example`.

## Checklist

- [ ] Create `topic-name/` with only the files that are needed
- [ ] `chmod +x topic-name/install.sh` when an installer exists
- [ ] Document public surface in `README.md`
- [ ] Mention the installer in `AGENTS.md` only if it changes a setup contract
- [ ] Run `tests/documentation_test.sh` and any relevant suite
- [ ] Run `zsh -n` / `sh -n` on new shell files

## When to use me

Use this when the user asks to add a new app/tool configuration topic to these
dotfiles (folder + default files + installer/docs wiring).
