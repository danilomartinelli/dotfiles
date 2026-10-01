# Codebase Structure

This is a topic-organized macOS configuration repository. Paths below are
relative to the repository root, not installed locations.

## 1) Top-Level Map

| Path                                                                                    | Purpose                                                                                             | Evidence                                                                             |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `bin/`                                                                                  | Public executables, including lifecycle, Git, mobile and key-creation adapters                      | `bin/dot`, `bin/mobile-setup`, `bin/ssh-key-create`                                  |
| `functions/`                                                                            | Zsh autoload functions and private completion helpers                                               | `functions/c`, `functions/_c`, `zsh/_startup.zsh`                                    |
| `_scripts/`                                                                             | Shared setup, discovery, linking, catalog readers, rendering and test runner                        | `_scripts/setup`, `_scripts/topic-catalog`, `_scripts/test`                          |
| `_macos/`                                                                               | macOS preferences catalog and applying adapters                                                     | `_macos/defaults.tsv`, `_macos/set-defaults.sh`                                      |
| `tests/`                                                                                | Isolated shell suites and reusable fixtures                                                         | `tests/_support/`, `tests/setup_test.sh`                                             |
| `homebrew/`, `mise/`                                                                    | Package-manager integration and runtime declarations                                                | `homebrew/_bundle.sh`, `mise/config.toml`                                            |
| `zsh/`, `system/`, `git/`, `workspace/`                                                 | Shell startup, environment, Git behavior and workspace creation                                     | `zsh/_startup.zsh`, `system/env.zsh`, `git/_branch-state.sh`, `workspace/install.sh` |
| `agents/`, `aider/`, `claude/`, `codex/`, `conductor/`, `hermes/`, `kimi/`, `opencode/` | Agent instructions, settings, installers or shell integrations                                      | `agents/install.sh`, `opencode/README.md`                                            |
| `android-studio/`, `xcode/`, `pnpm/`                                                    | Mobile readiness, SDK paths and package-manager paths                                               | `android-studio/_sdk.sh`, `xcode/install.sh`, `pnpm/path.zsh`                        |
| `aws/`, `docker/`, `homelab/`, `kubectl/`, `orbstack/`, `sentry/`, `tailscale/`         | Infrastructure CLI environment, aliases and selected application setup                              | Topic `aliases.zsh`, `homelab/install.sh`, `orbstack/docker.json`, `sentry/env.zsh`  |
| `direnv/`, `sops/`, `ssh/`                                                              | Trusted environment roots, encryption and SSH provisioning                                          | `direnv/install.sh`, `sops/create-key`, `ssh/install.sh`                             |
| `ghostty/`, `tmux/`, `vim/`, `zed/`                                                     | Terminal, multiplexer and editor settings                                                           | `ghostty/config`, `tmux/tmux.conf.symlink`, `vim/init.vim`, `zed/settings.json`      |
| `archiver/`, `bartender/`, `dock/`, `keyclu/`, `obsidian/`, `raycast/`, `skim/`         | Desktop preferences, app associations and shortcuts                                                 | Topic installers, `dock/_layout.tsv`, `obsidian/aliases.zsh`                         |
| `.github/`                                                                              | CI workflow, issue forms and PR template                                                            | `.github/workflows/ci.yml`, `.github/ISSUE_TEMPLATE/`                                |
| `.conductor/`                                                                           | This repository's workspace copy patterns and test command                                          | `.conductor/settings.toml`                                                           |
| `.agents/`, `.claude/`, `skills-lock.json`                                              | Project agent skills, compatibility links and upstream skill records                                | Tracked inventory, `skills-lock.json`, `CODING_STANDARDS.md`                         |
| `docs/agents/`, `docs/codebase/`                                                        | Agent workflow notes and this source map                                                            | `docs/agents/domain.md`, this directory                                              |
| `Brewfile`, `.commonrc`, `.localrc.example`, `dotfiles-root.symlink`                    | Software declarations, shared defaults, private-environment template and physical-checkout resolver | Corresponding root files                                                             |
| `README.md`, `AGENTS.md`, `CLAUDE.md`, `CODING_STANDARDS.md`                            | Public guide, agent procedure, `CLAUDE.md` link to `AGENTS.md`, normative rules                     | Corresponding root files                                                             |

`.context/` is ignored local work material. `.codegraph/` is a checkout index,
ignored through `git/gitignore.symlink`; `.conductor/settings.toml` includes
`.codegraph/**` and `.env*` for workspace copying. Neither is a source module.

## 2) Entry Points

- First installation: `_scripts/bootstrap` delegates to `_scripts/setup bootstrap`.
- Daily update: `bin/dot` resolves the checkout and delegates to
  `_scripts/setup update`; `--edit` executes the configured editor.
- Interactive shell: installed `~/.zshrc` links to `zsh/zshrc.symlink`, which
  resolves the checkout and sources `zsh/_startup.zsh`.
- Explicit operations: `bin/mobile-setup`, `bin/set-defaults`,
  `bin/ssh-key-create`, `bin/sops-key-create`, and `bin/nix-install`.
- Graphical setup checklist: `_scripts/setup checklist --open-apps`.
- Validation and rendering: `_scripts/test` and `_scripts/render-software-catalog`.
- `bin/git-*` commands are reached through Git's external-command mechanism;
  `functions/` entries are autoloaded through Zsh `fpath`.

There is no repository-owned HTTP server or worker entrypoint. Installed tools
may start their own processes; their implementations are outside this checkout.

## 3) Module Boundaries

| Boundary             | What belongs here                                                          | What must not be here                                    |
| -------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------- |
| Public adapters      | Arguments, checkout resolution, delegation                                 | Duplicate setup orchestration or link-conflict logic     |
| `_scripts/`          | Shared lifecycle and reusable mechanics                                    | Tool-specific credential payloads                        |
| Topic directory      | That tool's installer, shell integration and safe settings                 | Independent implementations of common installer guards   |
| Declarative catalogs | Ordered data consumed through shared readers                               | Duplicated imperative implementations of catalog parsing |
| `tests/`             | Temporary homes, controlled command stubs and assertions                   | Dependence on real credentials or package mutation       |
| Documentation        | Public guidance, normative rules, subsystem notes in their existing owners | Competing copies of the generated software catalog       |

These are the boundaries prescribed in `AGENTS.md` and
`CODING_STANDARDS.md`, with concrete implementations mapped in
`ARCHITECTURE.md`.

## 4) Naming and Organization Rules

- Topics and public commands use lowercase kebab-case. Internal modules commonly
  use an underscore prefix; tests use `*_test.sh`.
- `_scripts/topic-catalog` excludes hidden/underscore paths and reserves
  `bin`, `docs`, `functions`, and `tests` as non-topics.
- Direct `*.symlink` entries are link declarations. Other application files are
  linked explicitly by their topic installer.
- The classifier recursively discovers visible topic `.zsh` files, with special
  roles for `path.zsh`, `completion.zsh`, and `zsh/prompt.zsh`.
- Shell imports use resolved filesystem paths such as
  `$DOTFILES_ROOT/_scripts/catalog.sh`; there is no TypeScript alias map.
- `mise/mise.lock` and README software regions are generated artifacts.
  Machine-specific identity and rendered direnv settings remain ignored.
- `git ls-files` is necessary for a complete source inventory: the ignore pattern
  `*local*` also matches the tracked `bin/git-delete-local-merged`, which an
  ordinary ignore-aware file search can omit.

## 5) Evidence

- [Topic classifier](../../_scripts/topic-catalog),
  [checkout resolver](../../dotfiles-root.symlink)
- [Update adapter](../../bin/dot), [shell entry](../../zsh/zshrc.symlink)
- [Repository guide](../../AGENTS.md), [ignore rules](../../.gitignore)
- [Conductor repository configuration](../../.conductor/settings.toml),
  [global Git ignores](../../git/gitignore.symlink)
- [Documentation ownership](../../CODING_STANDARDS.md),
  [domain notes](../agents/domain.md)
