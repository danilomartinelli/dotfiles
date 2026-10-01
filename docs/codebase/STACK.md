# Technology Stack

Source baseline: `9acba575`, inspected on 2026-10-01 and updated with the local
cache/fixture corrections and the controlled-upgrade decision. These documents describe
repository source; they do not establish installed versions or successful
application to a Mac. `README.md` remains the public operating guide and
`CODING_STANDARDS.md` remains normative.

## 1) Runtime Summary

| Area                | Value                                                                                                                 | Evidence                                                                            |
| ------------------- | --------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Primary language    | POSIX shell, Bash and Zsh; TSV catalogs and application configuration                                                 | `_scripts/setup`, `_scripts/link-config`, `zsh/_startup.zsh`, `_macos/defaults.tsv` |
| Runtime + version   | System `/bin/sh`, Bash through `/usr/bin/env bash`, interactive Zsh; shell versions are not pinned by this repository | Script shebangs, `zsh/zshrc.symlink`, `Brewfile`, `mise/config.toml`                |
| Package managers    | Homebrew for system software; Mise for runtimes and language-distributed CLIs                                         | `Brewfile`, `mise/config.toml`, `mise/install.sh`                                   |
| Module/build system | Shell sourcing and executable adapters; no application compilation or root package-manager workspace                  | `_scripts/setup`, `_scripts/installer-preamble.sh`, tracked root inventory          |
| Target platform     | macOS with Git and Xcode Command Line Tools; some individual helpers also handle non-Darwin hosts                     | `README.md`, `homebrew/install.sh`, `_scripts/installer-preamble.sh`                |

Mise's checked-in lock resolves Node to `24.21.0`, Bun to `1.3.9`, and Python to
`3.14.7`. These are provisioned development tools. The upgrade coordinator and formatter
plugin reconciliation also use the declared Python interpreter. The Android system image and OpenCode native-binary repair name
`arm64`; Aider's Python path names `/opt/homebrew`. See
`_scripts/mobile-setup-android.sh`, `mise/install.sh`, and `mise/config.toml`.

## 2) Production Frameworks and Dependencies

There is no application server, ORM, dependency-injection framework, or
production/development dependency split. The operational dependencies are:

| Dependency                                  | Version policy                                                        | Role in system                                                   | Evidence                                                                                  |
| ------------------------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Git, Homebrew and Mise                      | Git/Homebrew not pinned; Mise declared as a Homebrew formula          | Checkout refresh and software reconciliation                     | `_scripts/setup`, `Brewfile`                                                              |
| macOS `defaults`, `duti`, `dockutil`, `mas` | OS tools or unpinned Homebrew declarations                            | Preferences, associations, Dock and App Store installation       | `_macos/set-defaults.sh`, `_scripts/installer-preamble.sh`, `dock/install.sh`, `Brewfile` |
| Declared Mise tools                         | Selectors in configuration; resolved releases/checksums in lock       | Language runtimes, coding agents and infrastructure CLIs         | `mise/config.toml`, `mise/mise.lock`                                                      |
| OpenCode CLI                                | `1.18.34`                                                             | Agent configuration consumer                                     | `mise/config.toml`, `opencode/install.sh`                                                 |
| OpenCode plugins                            | Anthropic auth `1.8.6`, DCP `3.2.0`, Markdown table formatter `0.0.6` | Plugins loaded by OpenCode, outside the installer implementation | `opencode/opencode.jsonc`                                                                 |
| SSH and age/SOPS                            | OS SSH and Homebrew declarations                                      | Explicit key creation and secret-file tooling                    | `ssh/create-key`, `sops/create-key`, `Brewfile`                                           |

The complete dependency inventory belongs to `Brewfile` and
`mise/config.toml`; the generated software tables in `README.md` expose every
declared package and its purpose. `mise/mise.lock` is generated, while
`Brewfile.lock.json` is ignored. Homebrew software is therefore not frozen to
one resolved package set. The public guide describes a declarative setup and
explicitly distinguishes configuration reproducibility from a frozen machine image.

## 3) Development Toolchain

| Tool                                  | Purpose                                              | Evidence                                                |
| ------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------- |
| ShellCheck                            | POSIX/Bash linting; lock resolves `0.11.0`           | `mise/mise.lock`, `.github/workflows/ci.yml`            |
| shfmt                                 | POSIX/Bash formatting; lock resolves `3.14.1`        | `mise/mise.lock`, `CODING_STANDARDS.md`                 |
| Zsh                                   | Syntax checks and startup fixtures                   | `.github/workflows/ci.yml`, `tests/zsh_startup_test.sh` |
| mdformat with GFM/frontmatter plugins | Markdown formatting; formatter lock resolves `1.0.0` | `mise/config.toml`, `mise/mise.lock`                    |
| Zed-managed Prettier, jq              | JSON/JSONC formatting and contract checks            | `.prettierrc.json`, `tests/zed_settings_test.sh`        |
| Custom Bash scenario harness          | Isolated behavioral tests                            | `tests/_support/shell-scenario.sh`                      |
| CodeGraph                             | Per-checkout index; CLI declaration `1.6.1`          | `mise/config.toml`, `agents/instructions.md`            |

CI consumes the same Mise lock for its check tools and explicitly pins formatter
extras, the Mise client, actions, and macOS major. The hosted image and transitive
language-package dependencies still evolve. See `TESTING.md`.

## 4) Key Commands

Installation and update commands mutate the machine and are documented here
only for navigation:

```bash
_scripts/bootstrap
bin/dot
```

Safe repository validation:

```bash
_scripts/test
_scripts/test documentation
_scripts/render-software-catalog --check
mise exec -- mdformat --check docs/codebase/*.md
git diff --check
```

There is no build or deploy command for a repository-owned application.
`CODING_STANDARDS.md` owns the complete static-check commands.

## 5) Environment and Config

- Public declarations: `Brewfile`, `mise/config.toml`, `_macos/defaults.tsv`,
  `dock/_layout.tsv`, `_scripts/_checklist.tsv`, and topic configuration files.
- Shell configuration: `.commonrc` and the secret-free `.localrc.example`.
  `.localrc` is created locally and restricted to mode `600`.
- `$HOME` identifies the installation target. `DOTFILES_ROOT` is resolved by
  adapters/preambles. `WORKSPACE` and `PROJECTS` have defaults in `.commonrc`.
- `DOTFILES_RESET` re-arms run-once operations;
  `XDG_STATE_HOME` controls their marker directory. Tool settings are linked
  beneath `$HOME/.config` regardless of `XDG_CONFIG_HOME`.
- Provider keys such as `CONTEXT7_API_KEY`, `KIMI_API_KEY`, and `ZHIPU_API_KEY`
  are optional integration-specific inputs, not universal bootstrap prerequisites.
- No dev/stage/production environment matrix or repository-owned container image
  is defined. OrbStack is an installed tool with Docker logging configuration.
- [TODO] Installed shell/tool versions and actual provider authentication were
  outside this source-only inspection.

## 6) Evidence

- [Declarations](../../Brewfile), [Mise configuration](../../mise/config.toml),
  [Mise lock](../../mise/mise.lock)
- [Setup](../../_scripts/setup), [Mise installer](../../mise/install.sh)
- [Environment example](../../.localrc.example), [shared defaults](../../.commonrc)
- [CI workflow](../../.github/workflows/ci.yml),
  [coding standards](../../CODING_STANDARDS.md)
