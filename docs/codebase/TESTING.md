# Testing Patterns

## 1) Test Stack and Commands

The primary runner is the repository's Bash `_scripts/test`, with a shared
scenario/assertion library in `tests/_support/shell-scenario.sh`. Neither has an
independent framework version: they are versioned with the repository.

```bash
# All safe suites; includes _scripts/test-checkout-root
_scripts/test

# Select suite names containing a substring
_scripts/test documentation
_scripts/test link_config
_scripts/test zsh_startup

# Read-only generated-output check
_scripts/render-software-catalog --check
```

There is no separate unit/integration/E2E command taxonomy or code-coverage
command. The same runner executes the selected shell suites and names every
failure. `CODING_STANDARDS.md` owns the focused validation matrix.

## 2) Test Layout

- `tests/*_test.sh`: discovered in sorted order by `_scripts/test`.
- `_scripts/test-checkout-root`: appended explicitly for checkout/symlink cases.
- `tests/_support/shell-scenario.sh`: temporary-root cleanup, assertions,
  per-case execution and final verdict.
- `tests/_support/fixture.sh`: installer home/state/fake-bin layout and per-run
  environment overrides.
- `tests/_support/stubs.sh`: shared fake external commands.
- `tests/_support/jsonc.sh`: comment-aware reading for configuration fixtures.
- `tests/_support/mobile-android-fixture.sh`: Android-specific fixture setup.
- `tests/documentation_test.sh`: intentional harness exception that collects all
  missing public documentation in one report.

At the inspected source snapshot the runner selects 32 suites, including the
checkout-root suite.

## 3) Test Scope Matrix

| Scope                                     | Covered?                    | Typical target                                                               | Notes                                                    |
| ----------------------------------------- | --------------------------- | ---------------------------------------------------------------------------- | -------------------------------------------------------- |
| Shared module behavior                    | Yes                         | Catalog and declaration reading, generated regions/files, Markdown tables    | Real filesystem and shell behavior in temporary fixtures |
| Process/filesystem integration            | Yes, isolated               | Setup ordering, symlink conflicts, key provisioning, Mise lock behavior      | Real repository scripts with fake vendor commands        |
| Interactive shell lifecycle               | Yes, isolated               | Zsh order, repeat sourcing, optional dependencies and agent aliases          | Separate `zsh -d -f` fixture process                     |
| Public documentation/config contracts     | Yes                         | Commands, aliases, packages, installer helpers, JSONC and renderer freshness | Primarily tracked source/config checks                   |
| Real package-manager/provider integration | Not part of safe suite      | Homebrew/Mise network installs, model auth, cloud CLIs                       | External calls are replaced by stubs                     |
| Real device/UI E2E                        | Not part of safe suite      | Simulator boot and graphical app behavior                                    | Requires separately authorized device/host work          |
| Performance/coverage measurement          | Not configured in runner/CI | Runtime benchmarks or line/branch coverage                                   | No numerical threshold or performance budget             |

Representative sources are `tests/catalog_test.sh`, `tests/setup_test.sh`,
`tests/link_config_test.sh`, `tests/mise_install_test.sh`,
`tests/zsh_startup_test.sh`, and `tests/mobile_setup_test.sh`.

## 4) Mocking and Isolation Strategy

`scenario_init` owns a temporary directory and exit cleanup. `fixture_run`
passes a temporary `HOME`, `XDG_STATE_HOME`, and a controlled
`fake-bin:/usr/bin:/bin` path. It clears `DOTFILES_RESET`, accepts per-command
environment overrides and captures stdout, stderr, and `SCENARIO_EVENT_LOG`.
Individual suites also construct specialized repositories and command stubs.

This is shell/process substitution at real integration boundaries, rather than
mocking an application's in-memory functions. Assertions check effects such as
link targets, backup files, permissions, execution order and command exit codes.

The isolated fixture environment is an explicit harness contract, not an OS
sandbox. A new test must stub each external operation it would otherwise reach.
Host PATH/environment leakage can invalidate isolation; see the safeguards in
`fixture_run` and `tests/mise_install_test.sh`.

## 5) Coverage and Quality Signals

- No code-coverage tool or percentage threshold is configured in the runner or
  `.github/workflows/ci.yml`. [TODO] Line/branch coverage is unmeasured.
- Documentation coverage checks public names, dependency declarations, shared
  installer helpers, Homebrew tap/trust agreement and generated README tables.
  It does not prove all narrative claims or integration readiness.
- Zsh fixtures cover repeated sourcing and nested topic additions and removals
  reaching the next shell. They unset the XDG cache, data and state homes, so
  startup writes only below the fixture's home.
- The classifier fixture runs discovery on a `PATH` holding only Bash and
  logging spies, and requires one `find` and one `sort` for several topics.
- [TODO] Historical flakiness and remote CI results were not inspected. A local
  result does not establish remote CI status.

GitHub Actions runs on `macos-15` for PRs, pushes to `main` and manual
invocation, with a 20-minute job timeout. It runs ShellCheck, shfmt, Zsh syntax,
Markdown formatting and `_scripts/test`. CI obtains its check tools through
`mise install --locked` against the repository config and lock. Formatter extras
have explicit versions, actions use full SHAs, and Mise has an explicit version.

Local validation on 2026-10-01: `_scripts/test` completed successfully with
**32 suites passed**. The seven-document section/link checks, Mise-managed
`mdformat --check`, and `git diff --check` also passed. These checks do not
include bootstrap, `dot`, live defaults, package mutations or credential creation
against the real home. The original nested-cache reproduction now passes,
and the durable startup regression covers the formerly missing case. Upgrade
fixtures cover cancellation, unattended execution, selection boundaries, channel
preservation, backend lock defaults, stale formatter extras, and failed installs
without rewriting source. Native Mise lock generation and a cold formatter
installation were also exercised separately in temporary directories.

## 6) Evidence

- [Runner](../../_scripts/test), [scenario harness](../../tests/_support/shell-scenario.sh)
- [Installer fixtures](../../tests/_support/fixture.sh),
  [shared stubs](../../tests/_support/stubs.sh)
- [Documentation checks](../../tests/documentation_test.sh),
  [Zsh fixtures](../../tests/zsh_startup_test.sh)
- [Mise fixtures](../../tests/mise_install_test.sh),
  [mobile fixtures](../../tests/mobile_setup_test.sh)
- [CI](../../.github/workflows/ci.yml), [validation matrix](../../CODING_STANDARDS.md)
