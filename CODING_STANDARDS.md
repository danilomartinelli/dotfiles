# Coding standards

Normative implementation, testing, and delivery rules for this personal macOS
dotfiles repository.

## Scope and precedence

These standards are written for the owner and experienced coding agents. They
apply repository-wide unless a closer `AGENTS.md` defines a narrower contract.

Use this precedence order:

1. Explicit user instructions define the requested outcome.
1. The closest applicable `AGENTS.md` defines the working procedure.
1. This file defines coding and validation standards.
1. `README.md` documents installation, operation, and public behavior.
1. Topic documentation owns subsystem-specific procedures.

Keep each fact in the narrowest authoritative document. Do not copy command
catalogs, validation lists, or subsystem runbooks between files.

## Engineering principles

- Change the narrowest source of truth and preserve unrelated work.
- Keep bootstrap, update, topic installers, and Zsh reloads idempotent.
- Separate repository state, installed machine state, and live external state.
- Prefer deterministic fixture tests to applying configuration on the real Mac.
- Make failure explicit and actionable; do not silently weaken a required step.
- Keep public adapters small and shared behavior in the owning private module.
- Remove code only when references, tests, and runtime ownership show it is dead.
- Optimize for readable control flow; avoid clever compression and deep nesting.

## Repository structure and naming

| Concern                              | Authoritative source              |
| ------------------------------------ | --------------------------------- |
| Homebrew software and its purposes   | `Brewfile`                        |
| Runtime and language-package tools   | `mise/config.toml`                |
| README software catalog tables       | rendered from the two files above |
| Resolved Mise versions and checksums | `mise/mise.lock`                  |
| macOS preferences                    | `_macos/defaults.tsv`             |
| Dock layout                          | `dock/_layout.tsv`                |
| Topic discovery and load classes     | `_scripts/topic-catalog`          |
| Setup orchestration                  | `_scripts/setup`                  |
| OpenCode and OCX configuration       | `opencode/`                       |
| Managed OpenCode entry catalog       | `opencode/_managed-entries.tsv`   |
| Shared OpenCode profile policy       | `opencode/profiles/_shared/`      |
| OpenCode profile model routing       | `opencode/profiles/_routing.tsv`  |
| Public commands and lifecycle        | `README.md`                       |
| Agent workflow                       | `AGENTS.md`                       |

Naming follows the executable surface already present:

- Public commands and topics use lowercase kebab-case, such as
  `ssh-key-create` and `android-studio`.
- Shell functions and internal variables use descriptive snake_case.
- Environment variables and cross-function constants use uppercase snake_case.
- Test functions begin with `test_`; shared test mechanics begin with
  `scenario_` or `assert_`.
- Stable public executables live in `bin/`; private orchestration lives in
  `_scripts/`.
- A topic installer is an executable direct child named exactly `install.sh`.

Do not rename a public command, environment variable, linked path, or profile
without updating adapters, tests, and user documentation in the same change.

## Shell scripts

### Dialect and entrypoints

- Use `#!/bin/sh` for portable POSIX shell and avoid Bash-only syntax there.
- Use `#!/usr/bin/env bash` only when arrays, `local`, process substitution,
  `BASH_SOURCE`, `pipefail`, or another Bash feature is required.
- Use `#!/usr/bin/env zsh` or a `.zsh` file for Zsh-only behavior.
- Executables may have a `.sh` suffix or no suffix; public `bin/` commands omit
  it.
- New Bash tests use `set -euo pipefail`. Match an existing script's stricter
  or compatibility-sensitive error mode when editing it.
- `pipefail` is not POSIX; enable it only in Bash or Zsh.

### Formatting and control flow

- Format POSIX and Bash files with `shfmt -i 2 -ci -bn`.
- Zed formats `Shell Script` buffers with the same flags through
  `mise exec -- shfmt`, so saving a file in the editor and running the static
  check produce identical output.
- Indent with two spaces and never with tabs.
- Do not run `shfmt` over Zsh-only syntax.
- Quote paths, parameter expansions, and command substitutions unless splitting
  is intentional, documented, and covered by ShellCheck suppression.
- Prefer `case` for multi-value dispatch and early returns for guard clauses.
- Keep pipelines and compound conditions readable; do not hide failures inside
  dense one-liners.
- Use arrays for argument lists in Bash or Zsh. POSIX shell callers should pass
  arguments positionally rather than constructing command strings.

### Functions and state

- Give functions one clear responsibility and use verb-led names.
- In Bash, declare function-local values with `local` before assigning command
  substitutions when preserving exit status matters.
- In POSIX shell, use lowercase temporary names and avoid leaking state across
  sourced boundaries.
- Never repurpose `HOME`, `PATH`, or other process-wide variables as scratch
  storage. Modify them only when that is the function's explicit contract.
- Use `mktemp` under `${TMPDIR:-/tmp}` and install cleanup traps for material
  temporary state.

### Output and errors

- Use `printf` instead of implementation-dependent `echo` behavior.

- Send normal results and progress to stdout; send warnings, errors, and usage
  failures to stderr.

- Use exit status `2` for invalid CLI usage and a nonzero status for operational
  failure.

- Topic installers source `_scripts/installer-preamble.sh` immediately after
  error-mode setup and use its shared interface:

  | Helper                       | Contract                                                           |
  | ---------------------------- | ------------------------------------------------------------------ |
  | `installer_require_darwin`   | Skip successfully outside macOS                                    |
  | `installer_require_command`  | Stop with an actionable formula hint when a required CLI is absent |
  | `installer_optional_command` | Warn and skip when an optional CLI is absent                       |
  | `installer_optional_app`     | Warn and skip when an optional application is absent               |
  | `installer_config_dir`       | Resolve a tool's configuration directory without creating it       |
  | `installer_workspace_root`   | Resolve the Workspace root without creating it                     |
  | `installer_skip_if_applied`  | Skip successfully when a run-once step has already been applied    |
  | `installer_mark_applied`     | Record that a run-once step completed                              |
  | `installer_claim_file_types` | Gate, apply, and record a topic's declared file-type associations  |

| `installer_apply_associations` | Apply a topic's declared file-type associations and report failures |
| `installer_link_config` | Delegate configuration linking to `_scripts/link-config` |
| `installer_banner` | Print a phase heading to stdout |
| `installer_success` | Print successful completion to stdout |
| `installer_note` | Print non-error detail to stdout |
| `installer_warn` | Print a warning to stderr |
| `installer_error` | Print an error to stderr |
| `installer_hint` | Continue a warning or error with an actionable stderr hint |
| `installer_fail` | Print an error and stop the installer |

Do not reimplement checkout resolution, Darwin checks, dependency hints,
message conventions, run-once markers, or link-conflict policy inside
individual installers.

Every tab-separated catalog is read through `_scripts/catalog.sh`, which the
preamble sources for installers and which `_macos/set-defaults.sh` and
`_scripts/setup` source directly. Call
`catalog_each_row <catalog> <handler>` and write a handler that takes the
row's four columns; do not write a `read` loop of your own. The reader owns
what counts as a comment, delivery of a final row with no trailing newline,
and reading on file descriptor 3 so a handler running `duti`, `dockutil`, or
`ocx` cannot consume the rows still to come. A handler must return zero:
consumers run under `set -e`, so a non-zero return stops the run rather than
skipping a row.

A tool's configuration directory is `installer_config_dir <tool>`, which
resolves `$HOME/.config/<tool>` and deliberately ignores `XDG_CONFIG_HOME`. Do
not reintroduce that variable in an installer, a `*.zsh` file, or a tracked
config payload: whether a tool honours it is the tool's fact to state, and Zed
does not on macOS. A single tool moves through its own variable, such as
`SOPS_AGE_KEY_FILE`. See
`docs/adr/0003-tool-config-directories-are-not-xdg-derived.md`.

A run-once step rebuilds state a person may have rearranged by hand, so it
applies on first run only. Gate it with `installer_skip_if_applied` and record
it with `installer_mark_applied`, both keyed by a short topic key. `DOTFILES_RESET`
re-arms one or more steps by key, or every step with `all`; nothing else may
define a per-topic reset variable.

A topic that claims file types declares them in `<topic>/_associations.tsv`
and claims them with `installer_claim_file_types`, which gates the run-once
step, requires `duti`, applies the catalog, and records the marker in that
order. Call it rather than spelling the sequence out: the run-once key is
derived from the topic directory, so no installer can gate on one key and mark
another, and the marker is written only after the apply returns.
`installer_apply_associations` remains the applying half for a topic that needs
it alone; no installer writes its own association loop. A row whose failure mode is `ignore` is best-effort,
because Launch Services does not recognise every identifier on every macOS
version, and only `report` rows are named and counted. Applying a catalog is a run-once
step in every topic that claims file types, so editing a row changes what the
next apply would set without setting it; `DOTFILES_RESET=<topic>-associations dot` applies it. See
`docs/adr/0005-file-type-associations-apply-once.md`.

A missing `duti` skips a topic's associations through
`installer_optional_command` rather than stopping the run. A default
application is a preference no later step consumes, and a topic that claims
file types has nothing else to do without it. Check the application the topic
configures before the tool that configures it, so a machine with neither is
told about the application it is missing.

Installer run order is declared, not alphabetical. `_scripts/setup` names the
prerequisite topics — those whose installers create state a later installer
consumes — and runs them before the rest, which follow in catalog order. Add a
topic to that list when another installer would otherwise read state that does
not exist yet; do not work around the ordering by recreating that state inside
the dependent installer.

## Zsh configuration

- Treat interactive Zsh as a reloadable module graph, not a one-shot script.
- Preserve the `_scripts/topic-catalog` loading order: `path.zsh`, other visible
  topic files, the authoritative prompt, completions, then syntax highlighting.
- Keep `path`, `fpath`, hooks, aliases, and cached implementation state
  de-duplicated after repeated `source ~/.zshrc` calls.
- Use Zsh arrays and conditionals where they make startup intent clearer.
- Keep prompt implementation in `zsh/prompt.zsh`; topics must not install a
  competing prompt.
- Validate every changed `.zsh` file with `zsh -n` and the startup fixture.

## JSON, JSONC, TOML, and declarative files

### JSON and JSONC

- Use double-quoted keys and strings and preserve the consumer's schema.
- Plain application data such as `orbstack/docker.json` must remain strict JSON.
- Zed's `settings.json` and `keymap.json` are JSONC-compatible despite their
  `.json` suffix. Comment-only lines are allowed, while formatter output omits
  trailing commas.
- OpenCode configuration uses `.jsonc`; retain comments only when they explain a
  non-obvious policy or compatibility constraint.
- Zed uses its managed Prettier for JSON and JSONC. The repository
  `.prettierrc.json` forces the `json` parser and disables trailing commas for
  `*.jsonc`, matching Zed's documented workaround.
- Do not add an external Prettier command to Zed settings unless Prettier is
  also declared and guaranteed on `PATH`.
- Reach a Mise-declared formatter from Zed through `mise exec` rather than a
  bare command name, because Zed does not inherit the interactive shell's
  Mise activation. Homebrew-provisioned formatters such as `nixfmt` are
  invoked directly.
- Validate JSONC with a comment-aware consumer or its focused test. Do not claim
  that strict `jq` accepts JSONC.

### TOML, Brewfile, and generated locks

- Preserve the established syntax and grouping in `mise/config.toml` and
  `Brewfile`.
- A trailing comment on a `brew`, `cask`, `mas`, or `[tools]` declaration is
  that entry's catalog description, and the comment above a `cask` block is its
  catalog group. `_scripts/render-software-catalog` renders both into
  `README.md`, so a declaration without one stops the render.
- Put runtimes and language-package CLIs in Mise; put system binaries,
  applications, fonts, MAS apps, and taps in Homebrew.
- A third-party Homebrew formula requires both its tap declaration and a narrow
  trust entry in `homebrew/_bundle.sh`.
- Regenerate `mise/mise.lock` with Mise from the repository root. Never edit its
  versions, checksums, or generated structure by hand.
- Keep other comments limited to ownership, compatibility, or non-obvious safety
  rationale, on their own line so they are not read as a catalog description.

## Markdown and documentation

- Use ATX headings, fenced code blocks with a language where applicable, and a
  single blank line around block elements.
- Keep lines readable and let the Mise-managed `mdformat` normalize wrapping,
  lists, and GFM tables.
- Zed formats Markdown with `mise exec -- mdformat`, not Prettier. Prettier's
  Markdown output does not satisfy `mdformat --check`, so enabling it drifts
  every file away from the format the static checks enforce.
- Use the repository `mdformat` installation with `mdformat-gfm` and
  `mdformat-frontmatter`; an unrelated bare installation can damage tables and
  skill frontmatter.
- Use inline code for commands, file paths, configuration keys, and literal
  values.
- Write comments and documentation to explain constraints and rationale, not to
  narrate obvious syntax.
- Keep `README.md` human-facing, `AGENTS.md` operational for agents, and this
  file normative. Detailed OpenCode procedures belong in `opencode/README.md`.
- Do not format registry-backed Markdown under `opencode/agents/`,
  `opencode/commands/`, `opencode/skills/`, or `opencode/tools/` independently.
  Those files must remain byte-identical to their OCX receipt; update them with
  OCX and validate integrity with `ocx verify`.
- Do not invent licenses, approvers, support channels, changelogs, or ownership
  beyond Danilo as the sole owner.

## Tests

- Cover behavior changes with isolated fixtures in `tests/`.
- Use temporary homes and fake external commands; never consume real
  credentials, package state, application state, or network services.
- Prefer the shared `tests/_support/shell-scenario.sh` mechanics for new
  scenario suites.
- Name a test after observable behavior, not an implementation detail.
- Assert exit status, stdout/stderr ownership, filesystem state, idempotency,
  and destructive boundaries where relevant.
- A focused test proves its contract only. Run the complete safe suite for
  shared setup, discovery, security, or repository-wide documentation changes.

### Focused validation matrix

| Change area                                                     | Required focused validation                                                                                  |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Public docs, commands, aliases, dependencies, installer helpers | `tests/documentation_test.sh`                                                                                |
| Setup phases and adapters                                       | `tests/setup_test.sh`                                                                                        |
| Zsh startup or topic shell files                                | `tests/zsh_startup_test.sh` and `zsh -n`                                                                     |
| Topic layout or discovery                                       | `tests/topic_catalog_test.sh`                                                                                |
| Checkout resolution                                             | `_scripts/test-checkout-root`                                                                                |
| Config and bootstrap links                                      | `tests/link_config_test.sh`, `tests/link_dotfiles_test.sh`                                                   |
| Shared installer helpers                                        | `tests/installer_preamble_test.sh`                                                                           |
| Catalog reading                                                 | `tests/catalog_test.sh`                                                                                      |
| Git helpers                                                     | `tests/git_branch_state_test.sh`                                                                             |
| Homebrew                                                        | `tests/homebrew_availability_test.sh`, `tests/homebrew_bundle_test.sh`, `tests/homebrew_maintenance_test.sh` |
| macOS defaults                                                  | `tests/macos_defaults_test.sh`                                                                               |
| SSH and SOPS                                                    | `tests/ssh_provisioning_test.sh`, `tests/sops_provisioning_test.sh`                                          |
| Archiver                                                        | `tests/archiver_install_test.sh`                                                                             |
| Dock layout                                                     | `tests/dock_install_test.sh`                                                                                 |
| OpenCode and OCX                                                | `tests/opencode_install_test.sh`                                                                             |
| Zed JSON and JSONC formatting                                   | `tests/zed_settings_test.sh`                                                                                 |

Run every safe test without maintaining a duplicated filename list:

```bash
for test_path in tests/*_test.sh; do
  "$test_path"
done
_scripts/test-checkout-root
```

Run applicable static checks:

```bash
git grep -IlzE '^#!.*(bin/sh|bash)([[:space:]]|$)' -- ':!*.md' \
  | xargs -0 shellcheck
git grep -IlzE '^#!.*(bin/sh|bash)([[:space:]]|$)' -- ':!*.md' \
  | xargs -0 shfmt -d -i 2 -ci -bn
git ls-files -z '*.zsh' | xargs -0 zsh -n
while IFS= read -r -d '' markdown_path; do
  [ ! -f "$markdown_path" ] || mdformat --check "$markdown_path"
done < <(
  git ls-files -z --cached --others --exclude-standard -- \
    '*.md' \
    ':(exclude)opencode/agents/**' \
    ':(exclude)opencode/commands/**' \
    ':(exclude)opencode/skills/**' \
    ':(exclude)opencode/tools/**'
)
git diff --check
```

All applicable formatters, linters, and tests must finish without errors or
warnings introduced by the change.

## Security and destructive boundaries

- Secrets belong in gitignored `.localrc` with mode `600` or an appropriate
  system credential store.
- Never log or commit Git identity, SSH private keys, SOPS identities,
  kubeconfigs, auth stores, OCX receipts, or account identifiers.
- SSH and SOPS installers may repair directories, links, and permissions; only
  the explicit `ssh-key-create` and `sops-key-create` commands create keys.
- Tracked Zed and OpenCode configuration must not contain plaintext credentials
  or fake interpolation for settings that treat `$VARIABLE` literally.
- Resolve exact targets before deletion, replacement, package mutation, or
  remote-changing commands.
- Tests must not run `_scripts/bootstrap`, `dot`, `set-defaults`, Homebrew
  mutation, credential creation against the real home, or destructive Git
  helpers.

## Git and delivery

- Make one logical change per commit, including its tests and documentation.
- Use a concise imperative summary consistent with repository history.
- Do not rewrite shared or published `main` history.
- Commit and push only with explicit authorization.
- Inspect the diff, run `git diff --check`, and stage only confirmed paths.
- After a push, verify that local and remote divergence is `0 0` and the
  worktree is clean.
- On macOS, add `-c core.fsmonitor=false` to Git inspection commands when the
  filesystem monitor is unavailable.

## Reference context

The external guides used to derive this file are context rather than authority:

- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Google JSON Style Guide](https://google.github.io/styleguide/jsoncstyleguide.xml)
- [Markdown Style Guide](https://cirosantilli.com/markdown-style-guide/)
- [Git Style Guide](https://github.com/agis/git-style-guide)

Repository behavior and the self-contained rules above take precedence.
