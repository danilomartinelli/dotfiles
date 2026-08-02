# AGENTS.md

Guidance for coding agents working in this personal macOS dotfiles repository.

## Scope and sources of truth

- `Brewfile` declares Homebrew formulae, casks, fonts, and the Xcode Mac App
  Store installation.
- `mise/mise.toml.symlink` declares language runtimes and global runtime tools.
- `README.md` documents the user-facing install/update workflow and every
  command, function, and alias exposed by the repository.
- `.localrc` and `git/gitconfig.local.symlink` are generated, gitignored,
  machine-private files. Never read secrets into logs or commit them.

This repository is macOS-first and assumes interactive Zsh. Tests use isolated
temporary homes and fixtures where possible.

## Commands

```bash
# First machine installation (interactive and machine-changing)
_scripts/bootstrap

# Daily checkout, Homebrew, and topic update
bin/dot
# Once the shell is configured:
dot

# Open the active checkout
dot --edit

# Tests
tests/setup_test.sh
tests/zsh_startup_test.sh
tests/ssh_provisioning_test.sh
tests/documentation_test.sh
_scripts/test-checkout-root

# Shell/static validation
zsh -n path/to/file.zsh
shellcheck path/to/script
```

Do not run bootstrap, `dot`, `set-defaults`, Homebrew mutation commands, SSH key
creation, or destructive Git utilities merely to validate a change. Their
fixture tests are the safe verification path.

## Public versus internal directories

- `bin/` is public. Zsh adds every executable there to `PATH`. `git-*` files
  also become `git <subcommand>` commands.
- `functions/` is public Zsh `fpath`. Files without `_` are callable functions;
  `_name` files implement completion and are internal.
- `tests/` is intentionally named without `_`. It is not a shell topic and is
  never sourced or installed; the conventional name makes validation visible
  to tooling and contributors.
- `_scripts/`, `_macos/`, and underscore-prefixed files are private
  implementation excluded from topic discovery.
- `.context/` is disposable, gitignored Conductor/agent workspace state, not
  project configuration.

Current public executables are `battery-status`, `dns-flush`, `dot`, `e`,
`headers`, `set-defaults`, `ssh-key-create`, and the Git utilities `git-all`,
`git-amend`, `git-copy-branch-name`, `git-credit`,
`git-delete-local-merged`, `git-edit-new`, `git-nuke`, `git-promote`,
`git-rank-contributors`, `git-track`, `git-undo`, `git-unpushed`,
`git-unpushed-stat`, `git-up`, and `git-wtf`.

Current public autoload functions are `c`, `extract`, and `gf`; `pubkey` is
defined by `ssh/aliases.zsh`. Keep README coverage and
`tests/documentation_test.sh` passing when changing this surface.

## Topic architecture

Each visible top-level topic may contain:

```text
topic/
├── install.sh       # Optional setup dependency phase
├── *.symlink        # Linked to ~/.<basename> during bootstrap
├── path.zsh         # PATH extension, loaded first
├── aliases.zsh      # Main shell configuration
├── env.zsh          # Main shell configuration
├── completion.zsh   # Loaded after compinit
└── *.zsh            # Other main configuration
```

Exact conventions matter:

- Top-level `_` directories and nested `_` files/directories are ignored by
  topic discovery.
- Installers must be named `install.sh` and be executable.
- Only `*.symlink` files are automatically linked.
- Setup executes sorted, top-level `topic/install.sh` files only. It skips
  reserved topics and `homebrew/install.sh`, which has its own phase.

## Setup ownership and lifecycle

`_scripts/setup` is the canonical implementation with two modes:

- `bootstrap`: create the private environment and Git identity, install links,
  apply macOS defaults, ensure Homebrew, install the Brewfile, and run topic
  installers.
- `update`: repair `~/.dotfiles-root`, attempt `git pull`, update/upgrade
  Homebrew, reconcile the Brewfile, and rerun topic installers. It does not
  relink all dotfiles or apply macOS defaults.

`_scripts/bootstrap` and `bin/dot` are stable adapters. Required phases stop on
failure. Checkout pull, Homebrew update/upgrade, and hostname normalization are
advisory. Keep orchestration logic in `_scripts/setup`, not duplicated in the
adapters.

`homebrew/install.sh` only makes Homebrew available. The dependency phase taps
`xo/xo` before reconciling `Brewfile`. Topic installers currently configure
Archiver associations, the Dock, Mise runtimes, SSH config, and WezTerm
terminfo.

## Checkout-root contract

`dotfiles-root.symlink` is the sole checkout-root interface. It resolves
symlinks and returns the physical checkout containing an anchor, which keeps
commands local to the invoking Git worktree. `--install` repairs
`~/.dotfiles-root` but refuses to overwrite a regular file or directory.

Public adapters should resolve through `~/.dotfiles-root` and fall back to the
repository copy beside the adapter. Do not reintroduce fixed `~/.dotfiles`
paths. Validate changes with `_scripts/test-checkout-root`.

## Zsh startup contract

`zsh/zshrc.symlink` resolves the checkout, exports `DOTFILES_ROOT`, and sources
`zsh/_startup.zsh` once. The private startup module owns this order:

1. Set `PROJECTS=~/Code`; source optional `~/.localrc`, then `.commonrc`.
2. Discover `HOMEBREW_PREFIX`; initialize unique `PATH`, `MANPATH`, `fpath`, and
   autoload functions.
3. Source sorted visible `*/path.zsh` files.
4. Source other sorted visible topic `*.zsh` files except completions and the
   authoritative prompt.
5. Source `zsh/prompt.zsh` as the sole prompt.
6. Run `compinit` once and source sorted `*/completion.zsh` files.
7. Source optional Homebrew Zsh syntax highlighting last.

Reloading must keep paths, hooks, and implementation variables de-duplicated.
Validate any startup change with `tests/zsh_startup_test.sh`.

## SSH contract

`ssh/install.sh` runs non-interactively during bootstrap and updates. It repairs
permissions, links tracked `ssh/config`, preserves `~/.ssh/config_local`, and
moves a conflicting config to the first free backup suffix. It must never
generate, rotate, delete, or upload credentials.

`bin/ssh-key-create` is the explicit credential adapter. It delegates to
`ssh/create-key`, accepts `default`, `personal`, or `work`, uses Ed25519 unless
`--rsa` is provided, and refuses to overwrite either half of a key pair.
Validate with `tests/ssh_provisioning_test.sh`.

## Editing rules

- Preserve unrelated work in a dirty worktree.
- Add Homebrew dependencies to `Brewfile`, runtimes to
  `mise/mise.toml.symlink`, and public command documentation to `README.md`.
- New topic installers must be idempotent and non-interactive because both
  bootstrap and daily updates run them.
- Shell startup changes must remain safe to source repeatedly.
- Keep secrets in `.localrc` with mode `600`; shared non-secret environment
  belongs in `.commonrc`.
- Prefer fixture tests over commands that mutate the actual Mac.
