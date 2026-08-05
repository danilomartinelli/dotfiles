# AGENTS.md

Guidance for coding agents working in this personal macOS dotfiles repository.

## Scope and sources of truth

- `Brewfile` declares Homebrew formulae, casks, fonts, and the Xcode Mac App Store installation.
- `mise/mise.toml.symlink` declares language runtimes and global runtime tools.
- `README.md` documents the user-facing install/update workflow and every command, function, and alias exposed by the repository.
- `CLAUDE.md` points here so Claude Code and Cursor agents share one contract.
- `.localrc` and `git/gitconfig.local.symlink` are generated, gitignored, machine-private files. Never read secrets into logs or commit them.

This repository is macOS-first and assumes interactive Zsh. Tests use isolated temporary homes and fixtures where possible.

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
tests/sops_provisioning_test.sh
tests/git_branch_state_test.sh
tests/homebrew_availability_test.sh
tests/homebrew_bundle_test.sh
tests/link_config_test.sh
tests/link_dotfiles_test.sh
tests/installer_preamble_test.sh
tests/macos_defaults_test.sh
tests/documentation_test.sh
tests/topic_catalog_test.sh
_scripts/test-checkout-root

# Shell/static validation
zsh -n path/to/file.zsh
shellcheck path/to/script
```

Do not run bootstrap, `dot`, `set-defaults`, Homebrew mutation commands, SSH or SOPS key creation, or destructive Git utilities merely to validate a change. Their fixture tests are the safe verification path.

## Public versus internal directories

- `bin/` is public. Zsh adds every executable there to `PATH`. `git-*` files also become `git <subcommand>` commands.
- `functions/` is public Zsh `fpath`. Files without `_` are callable functions; `_name` files implement completion and are internal.
- `tests/` is intentionally named without `_`. It is not a shell topic and is never sourced or installed; the conventional name makes validation visible to tooling and contributors.
- `tests/_support/shell-scenario.sh` owns shared temporary lifecycle, fake-command creation, capture, assertions, and TAP reporting. Keep fake command behavior local to the suite that exercises it.
- `_scripts/`, `_macos/`, and underscore-prefixed files are private implementation excluded from topic discovery.
- `.context/` is disposable, gitignored Conductor/agent workspace state, not project configuration.

Current public executables are `battery-status`, `dns-flush`, `dot`, `e`, `headers`, `set-defaults`, `sops-key-create`, `ssh-key-create`, and the Git utilities `git-all`, `git-amend`, `git-copy-branch-name`, `git-credit`, `git-delete-local-merged`, `git-edit-new`, `git-nuke`, `git-promote`, `git-rank-contributors`, `git-track`, `git-undo`, `git-unpushed`, `git-unpushed-stat`, `git-up`, and `git-wtf`.

Current public autoload functions are `c`, `extract`, and `gf`; `pubkey` is defined by `ssh/aliases.zsh`. Keep README coverage and `tests/documentation_test.sh` passing when changing this surface.

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

- Top-level `_` directories and nested `_` files/directories are ignored by topic discovery. The visible roots `bin/`, `functions/`, and `tests/` are explicit non-topics and are never classified as topics.
- `_scripts/topic-catalog <repository-root>` is the single private interface that classifies the layout for setup, Zsh startup, and the documentation test. It emits sorted, tab-separated `kind<TAB>absolute-path` records with kinds `topic`, `link`, `installer`, `path`, `main`, `prompt`, `completion`, and `aliases` (`aliases.zsh` emits both `main` and `aliases`; only `zsh/prompt.zsh` is the authoritative prompt).
- Installers must be named `install.sh` and be executable.
- Topic installers source `_scripts/installer-preamble.sh` after `set -e` / `set -eu` (set `INSTALLER_ANCHOR` when `$0` is wrong, e.g. bash via `BASH_SOURCE`). That preamble exports `TOPIC_DIR` and `DOTFILES_ROOT`, and provides `installer_require_darwin`, `installer_link_config`, and the inner output helpers (`installer_banner` / `installer_success` / `installer_note` / `installer_warn` / `installer_error` / `installer_hint`). `banner`, `success`, and `note` write to stdout; `warn`, `error`, and `hint` write to stderr, so a hint stays on the same stream as the warning or error it continues. Do not reintroduce per-installer path resolution, Darwin-guard boilerplate, or raw `echo` messages.
- Only `*.symlink` files are automatically linked.
- Setup executes sorted, top-level `topic/install.sh` files only. It skips reserved topics and `homebrew/install.sh`, which has its own phase.

## Setup ownership and lifecycle

`_scripts/setup` is the canonical implementation with two modes:

- `bootstrap`: create the private environment and Git identity, install links, apply macOS defaults, ensure Homebrew, install the Brewfile, and run topic installers.
- `update`: repair `~/.dotfiles-root`, attempt `git pull`, update/upgrade Homebrew, reconcile the Brewfile, and rerun topic installers. It does not relink all dotfiles or apply macOS defaults.

`_scripts/bootstrap` and `bin/dot` are stable adapters. Required phases stop on failure. Checkout pull, Homebrew update/upgrade, and hostname normalization are advisory. Keep orchestration logic in `_scripts/setup`, not duplicated in the adapters.

`_scripts/link-dotfiles` owns bootstrap home linking for `.localrc` and topic `*.symlink` files (interactive prompts, or `--batch skip|overwrite|backup` for fixtures). `_scripts/link-config` owns non-interactive topic config linking with policies `replace-with-backup` (default), `preserve-existing`, and `numbered-backup`.

`homebrew/install.sh` only makes Homebrew available. The private executable `homebrew/_availability.sh` owns executable discovery, prefix validation, and the non-failing startup fallback shared by installation, setup, and Zsh. `homebrew/_bundle.sh` owns Brewfile reconciliation and the small trust list (`nikitabobko/tap`); taps are declared in `Brewfile`. Topic installers currently configure Archiver, Dock, Mise, SSH, SOPS directories, Workspace (`~/Workspace/github.com/<user>`), Ghostty, Zed, Neovim (`~/.config/nvim/init.vim` bridge), AeroSpace, OrbStack, Bartender, KeyClu, Raycast script commands, Tailscale, OpenCode, and Hermes Agent (`~/.hermes`).

macOS system preferences live in `_macos/defaults.tsv` and are applied by `_macos/set-defaults.sh` (catalog critical; DNS/Library/restart advisory). App-specific `defaults write` calls stay in topic installers.

Project agent skills live in `.agents/skills/*/SKILL.md` (discovered by OpenCode). Use the `add-topic` skill when scaffolding a new topic folder.

## Checkout-root contract

`dotfiles-root.symlink` is the sole checkout-root interface. It resolves symlinks and returns the physical checkout containing an anchor, which keeps commands local to the invoking Git worktree. `--install` repairs `~/.dotfiles-root` but refuses to overwrite a regular file or directory.

Public adapters source `_scripts/adapter-checkout.sh` (set `ADAPTER_ANCHOR` when `$0` is wrong, e.g. Zsh startup). That preamble prefers `~/.dotfiles-root` and falls back to the sibling `dotfiles-root.symlink`. Do not reintroduce fixed `~/.dotfiles` paths. Validate changes with `_scripts/test-checkout-root`.

## Zsh startup contract

`zsh/zshrc.symlink` resolves the checkout, exports `DOTFILES_ROOT`, and sources `zsh/_startup.zsh` once. The private startup module owns this order:

1. Set `PROJECTS=~/Workspace/github.com`; source optional `~/.localrc`, then `.commonrc`.
1. Discover `HOMEBREW_PREFIX`; initialize unique `PATH`, `MANPATH`, `fpath`, and autoload functions.
1. Source sorted visible `*/path.zsh` files.
1. Source other sorted visible topic `*.zsh` files except completions and the authoritative prompt.
1. Source `zsh/prompt.zsh` as the sole prompt.
1. Run `compinit` once and source sorted `*/completion.zsh` files.
1. Source optional Homebrew Zsh syntax highlighting last.

Reloading must keep paths, hooks, and implementation variables de-duplicated. Validate any startup change with `tests/zsh_startup_test.sh`.

## SSH contract

`ssh/install.sh` runs non-interactively during bootstrap and updates. It repairs permissions, links tracked `ssh/config`, preserves `~/.ssh/config_local`, and moves a conflicting config to the first free backup suffix. It must never generate, rotate, delete, or upload credentials.

`bin/ssh-key-create` is the explicit credential adapter. It delegates to `ssh/create-key`, accepts `default`, `personal`, or `work`, uses Ed25519 unless `--rsa` is provided, and refuses to overwrite either half of a key pair. Validate with `tests/ssh_provisioning_test.sh`.

## SOPS contract

`sops/install.sh` ensures `~/.config/sops/age/` exists with safe permissions and repairs modes on existing identities. It must never generate, rotate, delete, or print private key material.

`bin/sops-key-create` is the explicit credential adapter. It delegates to `sops/create-key`, accepts `default`, `personal`, or `work`, writes an age identity under `~/.config/sops/age/`, writes a matching `recipient*.txt`, and refuses to overwrite existing files. Validate with `tests/sops_provisioning_test.sh`.

## Editing rules

- Preserve unrelated work in a dirty worktree.
- Add Homebrew dependencies to `Brewfile`, runtimes to `mise/mise.toml.symlink`, and public command documentation to `README.md`.
- New topic installers must be idempotent and non-interactive because both bootstrap and daily updates run them.
- Shell startup changes must remain safe to source repeatedly.
- Keep secrets in `.localrc` with mode `600`; shared non-secret environment belongs in `.commonrc`.
- Prefer fixture tests over commands that mutate the actual Mac.
- Prefer `mdformat` (no aggressive wrap that collapses tables) and `shfmt -i 2` for Markdown and POSIX/bash shell scripts; do not run `shfmt` on Zsh topic files that use Zsh-only syntax.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues, managed via `gh`. See `_docs/agents/issue-tracker.md`.

### Triage labels

Default canonical labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `_docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `CONTEXT.md` + `_docs/adr/`. See `_docs/agents/domain.md`.
