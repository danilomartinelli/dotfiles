# Repository guide for coding agents

## Project overview

This repository is the source of truth for Danilo Martinelli's personal macOS
environment. It declares Homebrew software, Mise-managed runtimes, macOS
defaults, Zsh startup, public shell commands, application configuration, and
idempotent topic installers.

This is an operating-system configuration repository, not an application with
a build artifact or deployment pipeline. Applying it changes the current Mac;
prefer fixture tests for development and validation.

Danilo is the sole owner unless a user request says otherwise. Do not invent
reviewers, approvers, teams, or external stakeholders.

## Instruction and documentation map

- `AGENTS.md` gives repository-wide instructions to coding agents.
- `GUIDELINES.md` is the detailed engineering and safety reference.
- `README.md` is the human-facing installation, operation, and command guide.
- `opencode/README.md` documents the OCX-managed OpenCode workspace.
- `opencode/profiles/*/AGENTS.md` files are versioned profile payloads. They
  configure OpenCode sessions; they are not substitutes for this root guide.

Explicit user instructions take precedence. For files below a nested
`AGENTS.md`, also follow the closest applicable instructions.

## Repository layout

```text
dotfiles/
├── bin/                  # Public executables added to PATH
├── functions/            # Public Zsh autoload functions
├── tests/                # Isolated behavioral and contract tests
├── _scripts/             # Private setup, linking, and discovery machinery
├── _macos/               # macOS defaults catalog and adapters
├── opencode/             # Dotfiles-owned OpenCode/OCX configuration
├── <topic>/              # Tool-specific shell files and optional installer
├── Brewfile              # Homebrew package and application declarations
├── mise/config.toml      # Runtime and language-package CLI declarations
├── mise/mise.lock        # Generated Mise resolution lock
└── .localrc.example      # Secret-free template for machine-local settings
```

Visible top-level directories are topics unless `_scripts/topic-catalog`
classifies them as reserved. `bin/`, `functions/`, and `tests/` are explicitly
not topics. Names beginning with `_` or `.` are excluded from public topic
discovery.

## Start every task safely

1. Inspect the checkout before editing:

   ```bash
   git -c core.fsmonitor=false status --short --branch
   git -c core.fsmonitor=false diff
   ```

1. Preserve unrelated tracked and untracked changes. Never discard or rewrite
   user work to obtain a clean tree.

1. Locate the owning topic, installer, tests, and documentation with `rg` and
   `rg --files` before changing behavior.

1. Distinguish repository state, local installed state, and live service state.
   A source diff does not prove that configuration was applied to the Mac.

1. Read files such as `.localrc.example`; never read or print `.localrc`, auth
   stores, private keys, kubeconfigs, or generated local Git identity.

## Sources of truth

| Concern                                         | Source                       |
| ----------------------------------------------- | ---------------------------- |
| Homebrew taps, formulae, casks, fonts, MAS apps | `Brewfile`                   |
| Runtime and language-package CLIs               | `mise/config.toml`           |
| Resolved Mise versions and checksums            | `mise/mise.lock` (generated) |
| macOS preferences                               | `_macos/defaults.tsv`        |
| Topic discovery and loading classes             | `_scripts/topic-catalog`     |
| Setup orchestration                             | `_scripts/setup`             |
| OpenCode global workspace                       | `opencode/`                  |
| Human-visible commands and lifecycle            | `README.md`                  |
| Engineering contracts                           | `GUIDELINES.md`              |

Do not edit `mise/mise.lock` by hand. Use the repository-root Mise workflow
when a declaration changes and review generated lock changes narrowly.

## Topic and installer conventions

A topic may contain:

```text
topic/
├── install.sh       # Optional non-interactive, idempotent installer
├── *.symlink        # File or directory linked into HOME
├── path.zsh         # PATH setup, loaded first
├── aliases.zsh      # Main shell configuration
├── env.zsh          # Main shell configuration
├── completion.zsh   # Loaded after compinit
└── *.zsh            # Other visible Zsh configuration
```

- Installers must be executable and named exactly `install.sh`.
- Source `_scripts/installer-preamble.sh` after `set -e` or `set -eu`.
- Use the preamble's guards, messages, and `installer_link_config`; do not
  duplicate checkout resolution, Darwin checks, dependency hints, or linking.
- Installers run during both bootstrap and updates. They must be idempotent,
  non-interactive, and safe to rerun.
- Only `*.symlink` entries are linked automatically.
- Shell startup must remain safe to source repeatedly and preserve ordering.

## Dependency placement

- Put system binaries, libraries, Homebrew applications, fonts, and taps in
  `Brewfile`.
- Put npm, PyPI/pipx, Ruby gem, Go module, and other language-package CLIs in
  `mise/config.toml`.
- Add third-party taps to both `Brewfile` and the narrow trust flow in
  `homebrew/_bundle.sh`.
- Update the dependency catalog in `README.md` in the same change.
- Do not run broad package-manager repair commands such as `npm audit fix` in
  this repository.

## OpenCode and OCX contract

`opencode/install.sh` initializes OCX and links only dotfiles-owned entries
into `~/.config/opencode`. Dotfiles owns `agents/`, `commands/`, `skills/`,
`tools/`, managed profiles, `ocx.jsonc`, `opencode.jsonc`, and `tui.jsonc`.

OCX owns `.ocx/`, `plugins/`, `package.json`, `.gitignore`, and
`profiles/default/`. Never copy or version those runtime paths. When adding a
managed profile or entry, update all of these together:

- `opencode/install.sh`
- `opencode/README.md`
- `tests/opencode_install_test.sh`

Install `regular` first and clone `go` and `boost` from it. Keep shared profile
instructions, OCX policy, permissions, MCPs, and researcher shell policy equal;
specialize their model routing and model-specific options.

Validate model IDs and variants against the live `opencode models <provider> --verbose --pure` catalog. A variant name is model-specific; do not invent a
universal `fast`, `max`, or reasoning option.

## Commands and validation

Do not run `_scripts/bootstrap`, `dot`, `set-defaults`, Homebrew mutation,
credential creation, or destructive Git utilities merely to validate a patch.
Use isolated tests instead.

Run the focused test for the area changed, then expand validation in proportion
to risk:

| Area                             | Validation                                                                                                   |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Documentation and public surface | `tests/documentation_test.sh`                                                                                |
| Setup orchestration              | `tests/setup_test.sh`                                                                                        |
| Zsh loading and idempotency      | `tests/zsh_startup_test.sh`                                                                                  |
| Topic classification             | `tests/topic_catalog_test.sh`                                                                                |
| Checkout resolution              | `_scripts/test-checkout-root`                                                                                |
| Config and home links            | `tests/link_config_test.sh`, `tests/link_dotfiles_test.sh`                                                   |
| Installer preamble               | `tests/installer_preamble_test.sh`                                                                           |
| Git branch helpers               | `tests/git_branch_state_test.sh`                                                                             |
| Homebrew contracts               | `tests/homebrew_availability_test.sh`, `tests/homebrew_bundle_test.sh`, `tests/homebrew_maintenance_test.sh` |
| macOS defaults                   | `tests/macos_defaults_test.sh`                                                                               |
| SSH and SOPS                     | `tests/ssh_provisioning_test.sh`, `tests/sops_provisioning_test.sh`                                          |
| Archiver                         | `tests/archiver_install_test.sh`                                                                             |
| OpenCode/OCX                     | `tests/opencode_install_test.sh`                                                                             |

For a repository-wide change, the safe complete suite is:

```bash
tests/setup_test.sh
tests/zsh_startup_test.sh
tests/ssh_provisioning_test.sh
tests/sops_provisioning_test.sh
tests/git_branch_state_test.sh
tests/homebrew_availability_test.sh
tests/homebrew_bundle_test.sh
tests/homebrew_maintenance_test.sh
tests/archiver_install_test.sh
tests/link_config_test.sh
tests/link_dotfiles_test.sh
tests/installer_preamble_test.sh
tests/macos_defaults_test.sh
tests/documentation_test.sh
tests/topic_catalog_test.sh
tests/opencode_install_test.sh
_scripts/test-checkout-root
```

Also run applicable static checks:

```bash
zsh -n path/to/file.zsh
shellcheck path/to/script.sh
shfmt -d -i 2 -ci -bn path/to/script.sh
mdformat --check path/to/document.md
git diff --check
```

Never run `shfmt` on Zsh files that use Zsh-only syntax. The Mise-managed
`mdformat` includes the required GFM and frontmatter plugins; a bare unrelated
installation can damage tables and skill frontmatter.

## Style and editing rules

- Follow the language and formatting already used by neighboring files.
- Prefer portable POSIX shell for `#!/bin/sh`; use Bash or Zsh features only in
  files with the matching shebang.
- Quote paths and parameter expansions unless intentional shell splitting is
  documented and tested.
- Use `printf` rather than unportable `echo` behavior in scripts.
- Keep public adapters small; put shared behavior in the owning private module.
- Add or update fixture tests for behavior changes.
- Keep README claims human-facing and current. Put detailed contributor
  contracts here or in `GUIDELINES.md`, and OpenCode operations in its topic
  README.
- Do not add license, contribution, or changelog sections to `README.md`.

## Security boundaries

- Secrets belong only in gitignored `.localrc` with mode `600` or in an
  appropriate system credential store.
- Generated `git/gitconfig.local.symlink`, SSH private keys, SOPS identities,
  kubeconfigs, account identifiers, and auth receipts are machine-private.
- SSH and SOPS installers may repair directories, links, and permissions; they
  must never generate, rotate, delete, upload, or print credentials.
- Tracked Zed JSON must not contain plaintext credentials or fake environment
  interpolation. Use OAuth or a process that reads inherited environment.
- Before destructive or remote-changing commands, resolve the exact target and
  ensure the user explicitly authorized that action.

## Commit and publication workflow

Commit or push only when explicitly requested.

1. Review `git status`, `git diff`, and `git diff --check`.

1. Stage only confirmed paths, even when the user authorizes all task changes.

1. Commit with a concise imperative message matching repository history.

1. Push the requested branch explicitly, for example `git push origin main`.

1. Verify the local branch and remote are synchronized:

   ```bash
   git -c core.fsmonitor=false status --short --branch
   git -c core.fsmonitor=false rev-list --left-right --count origin/main...main
   ```

If Git reports `fsmonitor_ipc__send_query` errors, repeat inspection commands
with `git -c core.fsmonitor=false`. Do not reset or recreate the checkout.

## Definition of done

A change is complete only when the requested files are implemented, relevant
tests and format checks pass, the diff contains no unrelated work, user-facing
documentation matches behavior, and any explicitly requested push is verified
on the target branch.
