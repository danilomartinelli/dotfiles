# Coding Conventions

This is an implementation map, not a second rulebook. `AGENTS.md` and
`CODING_STANDARDS.md` own the normative rules; examples below locate them.

## 1) Naming Rules

| Item                   | Rule                                                                                                            | Example                                          | Evidence                                           |
| ---------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ | -------------------------------------------------- |
| Public commands/topics | Lowercase kebab-case                                                                                            | `ssh-key-create`, `android-studio`               | `bin/ssh-key-create`, `android-studio/install.sh`  |
| Private modules        | Underscore prefix where excluded from topic loading                                                             | `_startup.zsh`, `_branch-state.sh`               | `zsh/`, `git/`, `_scripts/topic-catalog`           |
| Functions              | Descriptive snake_case, generally verb-led                                                                      | `install_topics`, `installer_link_config`        | `_scripts/setup`, `_scripts/installer-preamble.sh` |
| Shell variables        | Lowercase temporary values; uppercase exported/shared constants                                                 | `relative_installer`, `DOTFILES_ROOT`            | `_scripts/setup`                                   |
| Private sourced state  | Prefix identifies owner; cleanup avoids leakage                                                                 | `_catalog_*`, `_installer_*`, `_kp_*`            | Catalog, preamble and key-provisioning modules     |
| Types/interfaces       | No language-level type/interface convention in the shell core; module APIs are functions and argument contracts | `catalog_each_row <catalog> <handler>`           | `_scripts/catalog.sh`                              |
| Tests                  | `tests/*_test.sh`, `test_*`, `scenario_*`, `assert_*`                                                           | `test_every_agent_reads_the_shared_instructions` | `tests/agents_install_test.sh`                     |

The examples are backed by the public adapters, shared modules, fixtures, and
topic files mapped in `STRUCTURE.md`, rather than by generated or vendored code.

## 2) Formatting and Linting

- POSIX/Bash: ShellCheck and `shfmt -i 2 -ci -bn`; use two-space indentation.
  Zsh-only syntax is checked with `zsh -n`, never formatted with shfmt.
- Markdown: Mise-managed mdformat with GFM and frontmatter plugins. Vendored
  `.agents/` payloads are excluded by the documented checks and CI.
- JSON/JSONC: double-quoted strings; Zed-managed Prettier uses the repository
  `.prettierrc.json` override to parse JSONC without trailing commas.
- TOML/Brewfile: stay within the closed literal grammars that
  `_scripts/declared_software.py` reads (ADR-0002), and preserve grouping and
  declaration comments. The comments are catalog descriptions consumed by
  `_scripts/render-software-catalog`.
- Shell dialect follows the shebang. Bash-only arrays, `local`, and `pipefail`
  do not belong in `#!/bin/sh` scripts.

For a changed file, the corresponding commands are:

```bash
shellcheck path/to/changed-script
shfmt -d -i 2 -ci -bn path/to/changed-script
zsh -n path/to/changed-file.zsh
mise exec -- mdformat --check path/to/changed-document.md
git diff --check
```

`CODING_STANDARDS.md` and `.github/workflows/ci.yml` define the actual
repository-wide selection commands. No TypeScript strictness configuration is
part of the current repository-owned shell implementation.

## 3) Import and Module Conventions

- A topic installer sources `_scripts/installer-preamble.sh` immediately after
  error-mode setup; it derives the topic/root from the installer location.
- Every other entry point resolves the checkout containing it in its first
  line and never reads an inherited `DOTFILES_ROOT` (ADR-0004).
- Sourced modules declare ShellCheck source hints or narrow suppressions when
  runtime-resolved paths prevent static resolution.
- Shared shell modules expose named functions; there are no package barrels or
  language import aliases. Zsh public functions are discovered through `fpath`.
- TSV catalog files use `catalog_each_row`, after `catalog_check` with the
  validator from the rules file beside the consumer. `topic-catalog` stdout is
  consumed directly, as prescribed in `CODING_STANDARDS.md`.
- Secrets and user-specific runtime files are not module payloads. Generated
  locks and README regions are changed through their owning generators.

## 4) Error and Logging Conventions

| Boundary     | Observed behavior                                                                                         | Evidence                                                         |
| ------------ | --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Setup        | `run_critical` stops on failure; `run_advisory` warns and continues                                       | `_scripts/setup`                                                 |
| Installer    | Shared banner/item/success output; warnings/errors on stderr; required versus optional dependency guards  | `_scripts/installer-output.sh`, `_scripts/installer-preamble.sh` |
| Linker       | `0` means linked or deliberately preserved; `1` operational failure; `2` invalid usage or refused removal | `_scripts/link-config`                                           |
| Key creation | Refuses existing material and preserves generator failure status                                          | `_scripts/key-provisioning.sh`                                   |
| Test runner  | Accumulates failed suites and emits one overall verdict                                                   | `_scripts/test`                                                  |

There is no structured logging library or mandatory trace-ID field. Messages
name the phase, command or path needed to diagnose a failure. Standards prefer
`printf`; some existing POSIX modules still use `echo` for simple messages, so
that preference is not a claim that every file already uses `printf`.

Credentials, private identity, auth stores, keys and account state must never be
printed or committed (`AGENTS.md`). This is a handling rule, not a centralized
runtime redaction facility.

## 5) Testing Conventions

- Use temporary homes and fake command binaries. Invoke fixture commands with
  per-run environment overrides through `fixture_run`.
- Use `scenario_run` so one failing case does not hide later cases.
  `tests/documentation_test.sh` intentionally accumulates coverage failures itself.
- Assert filesystem state, exit status, stream ownership, ordering, idempotency
  and refusal boundaries where relevant.
- Run the focused matrix in `CODING_STANDARDS.md`; shared/repository-wide work
  requires `_scripts/test`.
- No numeric code-coverage threshold is configured in `_scripts/test` or CI.
  Behavioral contracts are the current quality mechanism.
- `FAIL_<COMMAND>` or `FAIL_<COMMAND>_<SUBCOMMAND>` controls exit status;
  `FAKE_<COMMAND>_<NOUN>` supplies output or state. For duti, `FAIL_DUTI=1`
  selects the status and `FAKE_DUTI_IDENTIFIERS` optionally selects affected
  rows. Mise and mobile tool fixtures use the same status convention.

## 6) Evidence

- [Normative rules](../../CODING_STANDARDS.md), [repository procedure](../../AGENTS.md)
- [Formatting config](../../.prettierrc.json), [CI](../../.github/workflows/ci.yml)
- [Setup](../../_scripts/setup), [installer output](../../_scripts/installer-output.sh)
- [Harness](../../tests/_support/shell-scenario.sh),
  [fixture boundary](../../tests/_support/fixture.sh), [stubs](../../tests/_support/stubs.sh)
