# Codebase Concerns

Standing risks and trust boundaries of the current source. Corrected defects
are not kept here; Git history and the regression tests record them.

## 1) Top Risks

| Severity                         | Concern                                                                                                           | Evidence                                                               | Impact                                                                                                        | Suggested action                                                           |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Medium, reproducibility boundary | Homebrew installations, hosted runner images, and transitive language-package dependencies are not fully frozen   | `Brewfile`, `.gitignore`, `.github/workflows/ci.yml`, `mise/mise.lock` | New installations and transitive resolutions can still differ despite controlled upgrades and locked CI tools | Use the controlled-upgrade ADR and README boundaries when diagnosing drift |
| Low, compatibility               | `opencode/opencode.jsonc` keeps two keys its schema marks deprecated, because OpenCode 1 ignores the replacements | `opencode/opencode.jsonc`, `opencode/README.md`                        | A move to OpenCode v2 must rename both and move the Anthropic plugin to its `2.x` line                        | Follow the conditions in `opencode/README.md` before moving                |

## 2) Technical Debt

| Debt item            | Why it exists                                                                      | Where                                                                                                                  | Risk if ignored                                                     | Suggested fix                                                                              |
| -------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Large fixture suites | Suites contain setup and many cases; size alone does not establish a design defect | `tests/mobile_setup_test.sh`, `tests/installer_preamble_test.sh`, `tests/zsh_startup_test.sh`, `tests/catalog_test.sh` | Maintenance requires understanding fixture state and shared helpers | Use the owning shared fixture modules when extending behavior; avoid speculative splitting |

## 3) Security Concerns

These are existing trust boundaries, not claims of exploitation or new
vulnerabilities.

| Risk                                               | Evidence                                                       | Current mitigation                                                                  | Gap                                                                                           |
| -------------------------------------------------- | -------------------------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Remote installer supply-chain trust                | `homebrew/install.sh`, `bin/nix-install`                       | HTTPS; Homebrew content sanity check; Nix installation is explicit                  | No pinned checksum or signature verification in these wrappers                                |
| A dependency outside the declarations              | `herdr/install.sh`, `README.md`                                | Herdr installs `herdr-core` itself, on the owner's confirmation                     | Homebrew does not package it, so neither the Brewfile nor the upgrade picker sees its version |
| Project configuration executes under trusted roots | `_scripts/trusted-roots`, `direnv/install.sh`, `mise/mise.zsh` | One explicit root declaration shared by both tools                                  | Every project placed under a trusted prefix inherits this policy                              |
| User-state replacement during installation         | `_scripts/link-config`, `_scripts/key-provisioning.sh`         | Backups/preservation policies, dangerous-destination refusal, key-overwrite refusal | These guards do not replace correct caller destination selection                              |
| Agent/editor authority is broad by declaration     | `zed/settings.json`                                            | Source is inspectable; secrets remain outside tracked configuration                 | `trust_all_worktrees`, broad sandbox permissions and agent modes are permissive settings      |

## 4) Performance and Scaling Concerns

| Concern                     | Evidence                                        | Scaling risk                                                      | Suggested improvement                                                              |
| --------------------------- | ----------------------------------------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Discovery on every shell    | `zsh/_startup.zsh`, `_scripts/topic-catalog`    | Classifier cost is startup cost                                   | Keep it at one `find` and one `sort`; a cache needs a freshness rule of its own    |
| Ordered installer execution | `_scripts/setup`                                | Total setup time includes vendor operations executed sequentially | Preserve declared prerequisites; measure before considering concurrency            |
| Vendor device-call timeouts | `opencode/opencode.jsonc`, `opencode/README.md` | Provider/device latency is outside fixture timing                 | Keep diagnosis at the documented CLI/device boundary; measure the actual operation |

Shell-startup and complete setup latency are not benchmarked.

## 5) Areas to Review Carefully

| Area                                             | Why review carefully                                       | Safe change strategy                                   |
| ------------------------------------------------ | ---------------------------------------------------------- | ------------------------------------------------------ |
| `README.md`                                      | Public contracts and generated regions coexist             | Use the renderer and documentation checks              |
| `AGENTS.md`, `CODING_STANDARDS.md`               | Procedure and normative rules affect all work              | Cross-check current implementation and CI              |
| `mise/mise.lock`, `mise/config.toml`, `Brewfile` | Dependency declarations and resolved state differ          | Regenerate the lock through its owner; review narrowly |
| `tests/setup_test.sh`, `_scripts/setup`          | Phase ordering and failure contracts                       | Use the setup fixtures and complete safe runner        |
| Linked files their apps also write               | Both repository edits and application writes can affect it | Preserve unrelated app writes and run config checks    |

The last row covers `zed/settings.json`, `claude/settings.json`,
`herdr/settings.json` and `neovim/nvim-pack-lock.json`.

## 6) Evidence

- [Startup](../../zsh/_startup.zsh), [classifier](../../_scripts/topic-catalog),
  [startup fixtures](../../tests/zsh_startup_test.sh)
- [Dependencies](../../Brewfile), [lock](../../mise/mise.lock),
  [CI](../../.github/workflows/ci.yml), [ignore rules](../../.gitignore)
- [Installer download](../../homebrew/install.sh),
  [linker guards](../../_scripts/link-config), [key guards](../../_scripts/key-provisioning.sh)
- [Trusted roots](../../_scripts/trusted-roots), [editor settings](../../zed/settings.json)
- [Controlled-upgrade decision](../adr/0001-controlled-software-upgrades.md)
