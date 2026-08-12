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
directory, then call `installer_link_config` (default policy `replace-with-backup`).
Use `--policy preserve-existing` when local machine tweaks must win, or
`--policy numbered-backup` when collisions need free `.backup.N` suffixes (SSH).
Do not reimplement link/backup logic inside the installer.

## Installer scaffold

When an installer is needed, start from the shared preamble — never copy boilerplate
from another topic:

```sh
#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_darwin # omit when the topic is cross-platform
installer_banner "setting up topic-name"

# topic-specific work using $TOPIC_DIR, installer_link_config, etc.

installer_success "topic-name configured"
```

The preamble exports `TOPIC_DIR` and `DOTFILES_ROOT`, and provides
`installer_require_darwin`, `installer_require_command`, `installer_require_app`,
`installer_link_config`, `installer_banner`, `installer_success`,
`installer_note`, `installer_warn`, `installer_error`, and `installer_hint`. For
bash installers, set `INSTALLER_ANCHOR=${BASH_SOURCE[0]}` before sourcing.

Declare dependencies with the require helpers instead of hand-rolled checks:

```sh
# Hard CLI dependency — errors and exits 1 when missing.
# The Homebrew formula defaults to the command name.
installer_require_command duti

# Optional app — warns and exits 0 (skips the topic) when no candidate
# path exists; sets INSTALLER_APP to the first match.
installer_require_app Ghostty ghostty "/Applications/Ghostty.app"
```

Never write installer output with a raw `echo`. `banner`, `success`, and `note`
go to stdout; `warn`, `error`, and `hint` go to stderr. Use `installer_hint` —
not `installer_note` — for the actionable follow-up to a warning or error, so the
whole message stays on one stream:

```sh
installer_warn "Ghostty not installed yet"
installer_hint "Install with: brew install --cask ghostty"
```

## Rules

1. Topic directory name must not start with `_` and must not be `bin`,
   `functions`, or `tests`.
1. `install.sh` must use `set -e` (or `set -eu`), source the installer preamble,
   skip non-Darwin via `installer_require_darwin` when macOS-only, and be safe
   to run from both bootstrap and `dot`.
1. Do not generate credentials in installers. Use an explicit `bin/*-create`
   adapter when key material is needed (see SSH/SOPS).
1. If the topic adds Homebrew packages, update `Brewfile`.
1. If the topic adds runtimes/tools, update `mise/config.toml`.
1. Update `README.md` for every new public `bin/` command, alias, Brewfile
   package, and Mise tool — `tests/documentation_test.sh` enforces this.
1. Prefer fixture tests over mutating the real Mac.
1. Keep secrets out of the topic; document env vars in `.localrc.example`.

## Checklist

- [ ] Create `topic-name/` with only the files that are needed
- [ ] Scaffold `install.sh` from the preamble template above when an installer exists
- [ ] `chmod +x topic-name/install.sh` when an installer exists
- [ ] Document public surface in `README.md`
- [ ] Mention the installer in `AGENTS.md` only if it changes a setup contract
- [ ] Run `tests/documentation_test.sh` and any relevant suite
- [ ] Run `zsh -n` / `sh -n` on new shell files

## When to use me

Use this when the user asks to add a new app/tool configuration topic to these
dotfiles (folder + default files + installer/docs wiring).
