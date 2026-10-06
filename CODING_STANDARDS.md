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

| Concern                                        | Authoritative source              |
| ---------------------------------------------- | --------------------------------- |
| Homebrew software and its catalog descriptions | `Brewfile`                        |
| Runtime and language-package tools             | `mise/config.toml`                |
| README software catalog tables                 | rendered from the two files above |
| Resolved Mise versions and checksums           | `mise/mise.lock`                  |
| macOS preferences                              | `_macos/defaults.tsv`             |
| Dock layout                                    | `dock/_layout.tsv`                |
| Topic discovery and load classes               | `_scripts/topic-catalog`          |
| Setup orchestration                            | `_scripts/setup`                  |
| Global coding-agent instructions               | `agents/instructions.md`          |
| Trusted roots for direnv and Mise              | `_scripts/trusted-roots`          |
| Public commands and lifecycle                  | `README.md`                       |
| Agent workflow                                 | `AGENTS.md`                       |

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

  | Helper                         | Contract                                                            |
  | ------------------------------ | ------------------------------------------------------------------- |
  | `installer_require_darwin`     | Skip successfully outside macOS                                     |
  | `installer_require_command`    | Stop with an actionable formula hint when a required CLI is absent  |
  | `installer_optional_command`   | Warn and skip when an optional CLI is absent                        |
  | `installer_optional_app`       | Warn and skip when an optional application is absent                |
  | `installer_config_dir`         | Resolve a tool's configuration directory without creating it        |
  | `installer_workspace_root`     | Resolve the Workspace root without creating it                      |
  | `installer_skip_if_applied`    | Skip successfully when a run-once step has already been applied     |
  | `installer_mark_applied`       | Record that a run-once step completed                               |
  | `installer_claim_file_types`   | Check, gate, apply, and record a topic's file-type associations     |
  | `installer_apply_associations` | Check and apply a topic's declared associations and report failures |
  | `installer_link_config`        | Delegate configuration linking to `_scripts/link-config`            |
  | `installer_link_tool_config`   | Link one file into a tool's configuration directory                 |
  | `installer_banner`             | Print a phase heading to stdout                                     |
  | `installer_success`            | Print successful completion to stdout                               |
  | `installer_item`               | Print one completed step inside a phase, indented under it          |
  | `installer_note`               | Print non-error detail to stdout                                    |
  | `installer_warn`               | Print a warning to stderr                                           |
  | `installer_error`              | Print an error to stderr                                            |
  | `installer_hint`               | Continue a warning or error with an actionable stderr hint          |
  | `installer_fail`               | Print an error and stop the installer                               |

A topic that links a file into `$HOME/.config/<tool>` calls
`installer_link_tool_config`, which resolves the directory and composes the
destination. Reach for `installer_link_config` directly only to link outside
that directory or under a policy other than the default. The linker creates the
directory that holds a destination, so no installer runs `mkdir` just to
prepare a link.

Do not reimplement checkout resolution, Darwin checks, dependency hints,
message conventions, run-once markers, or link-conflict policy inside
individual installers.

The message helpers live in `_scripts/installer-output.sh`, which the preamble
sources, so an installer reaches them the same way as everything else. A module
an installer calls out to — `_scripts/link-config`, `_macos/set-defaults.sh`,
`_macos/set-hostname.sh` — sources that file directly rather than carrying its
own copy of the glyphs. `installer_success` closes the phase a banner opened and
`installer_item` reports one step inside it; the indent is what distinguishes
them, so a nested step uses `installer_item` rather than losing that level.

A command acts on the checkout that contains it
([ADR-0004](docs/adr/0004-each-entry-point-resolves-its-own-checkout.md)), so
every entry point resolves that checkout in its own first line rather than
through a shared module. A POSIX script writes
`DOTFILES_ROOT=$(CDPATH='' cd -P -- "$(dirname -- "$0")/.." && pwd)`, a Bash
script the same with `${BASH_SOURCE[0]}`, and `zsh/zshrc.symlink` resolves its
own path with `:A` because `~/.zshrc` links to it. A topic installer takes the
root from the preamble, which resolves `$0/..`. No executable reads an
inherited `DOTFILES_ROOT` or falls back to one: every shell exports its active
checkout's root, which is not the checkout a worktree's command belongs to. A
sourced file reads the value of the process that sourced it.

`_scripts/link-config --status <source> <destination>` reports what a
destination holds — `current`, `conflict`, or `absent` — and changes nothing. It is how
`_scripts/link-dotfiles` decides which conflict policy to ask for; no caller
derives that classification for itself.

On the acting path the linker's exit status is its outcome: `0` when the
destination matches the declaration or the policy kept it deliberately, `1` when the link
could not be made, and `2` for invalid usage or a removal it refuses to perform.
A caller does not parse the prose to learn which happened.

Every tab-separated catalog file is read through `_scripts/catalog.sh`, which
the preamble sources for installers and which `_macos/set-defaults.sh`,
and `_scripts/checklist` source directly. Call
`catalog_each_row <catalog> <handler>` and write a handler that takes the
leading columns it needs; do not write a `read` loop of your own. The reader
pads every row to seven arguments, and owns what counts as a
comment, delivery of a final row with no trailing newline, and reading on file
descriptor 3 so a handler running `duti` or `dockutil` cannot consume
the rows still to come. A handler must return zero: consumers run under
`set -e`, so a non-zero return stops the run rather than skipping a row.

A consumer checks its whole catalog with `catalog_check <catalog> <validator>`
before its first effect and before any run-once gate, and stops when it returns
non-zero. A row that is wrong on its text alone is a repository error: checked
while applying, it leaves the rows above it applied, and checked behind a gate,
it stays hidden until a reset. The validator is called like a handler and must
also return zero. It rejects a row through `catalog_reject <reason>`,
`catalog_reject_duplicate <column>...`, or
`catalog_reject_undeclared <value> <NAME> <replacement>...`, as many times as
the row has faults; the module prints each as `<catalog>:<line>: <reason>` and
the consumer adds one line in its own voice. A validator decides from the text
only. Whether an app exists or a tool accepts an identifier is a fact about the
machine, and stays a warning in the handler, which applies a checked row
without repeating the checks.

The validator lives in a rules file beside its consumer, such as
`dock/_layout-rules.sh`, so `tests/catalog_rules_test.sh` can run it over the
tracked catalog without running the consumer. That suite fails for a tracked
catalog missing from its table, so a new catalog gets a rules file and a row
there in the same change. A rules file declares the placeholders its catalog
honours once, in one function that forwards the same pairs to `catalog_expand`
or `catalog_reject_undeclared`, so no name is accepted without being expanded.
[ADR-0005](docs/adr/0005-validate-catalogs-before-any-effect.md) records why the
rules are shell rather than a schema declared in the catalog.

A catalog value that names a path through a placeholder is expanded with
`catalog_expand <value> <NAME> <replacement>...`, from the same module. The
caller names what its catalog honours and what each name stands for; the module
owns the `$NAME` grammar and the rule that every other `$` stays literal. Do not
reach for `sed`, `${var//}`, or a jq `sub()` at a call site, and do not read a
replacement out of the environment on the caller's behalf: passing it explicitly
is what keeps `eval` out of a module every installer sources.

A token ends where its name ends, so no honoured name may prefix another one in
the same call. A value substituted into JSON source text rather than into a
decoded string is escaped by its caller first: the module expands text and does
not know the syntax the result lands in. APFS allows both `"` and `\` in a path
component, so a checkout path spliced in raw is a value `jq` refuses to parse,
and `tests/catalog_test.sh` holds the module to that.

A catalog that arrives as a command's stdout rather than a file is read
directly by its consumer. `_scripts/topic-catalog` output is the only one.
Accepting stdin would surrender, for every consumer, the file descriptor 3 that
lets a handler run `duti` or `dockutil` without consuming the remaining rows,
and no consumer of that output runs such a handler. Widening a catalog past
seven columns means widening the reader first; a wider row packs its tail into
the last argument instead of failing.

A catalog row that names behaviour binds to it by convention rather than by a
`case` listing every pair, the way `_scripts/mobile-setup` composes
`<operation>_<target>`. The convention is only safe with the refusal that goes
with it: resolve the name, check it is defined, and stop the run when it is
not. A composed name that silently resolves to nothing is worse than the
enumeration it replaced, because a half-added row then does nothing at all
instead of failing.

A generated region inside a hand-authored Markdown file is read through
`_scripts/generated-region.sh`, which `_scripts/render-software-catalog`
sources directly. Call `generated_regions_render <source-file> <handler>` and
write a handler that prints one region's body for a name, or returns non-zero
for a name it does not know; do not write a marker loop of your own. The module
owns the marker syntax, the refusal of a file with no region or a malformed
one, byte-for-byte preservation of everything outside a region's interior, and
the blank lines Markdown puts around a body. It returns `2` for
invalid usage and `1` for any render failure. Output streams as it is
produced, so render into a staging file and pass it to `generated_file_sync`
only when the render returned zero.

A tool's configuration directory is `installer_config_dir <tool>`, which
resolves `$HOME/.config/<tool>` and deliberately ignores `XDG_CONFIG_HOME`. Do
not reintroduce that variable in an installer, a `*.zsh` file, or a tracked
config payload: whether a tool honours it is the tool's fact to state, and Zed
does not on macOS. A single tool moves through its own variable, such as
`SOPS_AGE_KEY_FILE`.

A run-once step rebuilds state a person may have rearranged by hand, so it
applies on first run only. Gate it with `installer_skip_if_applied` and record
it with `installer_mark_applied`, both keyed by a short topic key. `DOTFILES_RESET`
re-arms one or more steps by key, or every step with `all`; nothing else may
define a per-topic reset variable.

A topic that claims file types declares them in `<topic>/_associations.tsv`
and claims them with `installer_claim_file_types`, which checks the catalog,
gates the run-once step, requires `duti`, applies the catalog, and records the
marker in that order. Call it rather than spelling the sequence out: the
run-once key is derived from the topic directory, so no installer can gate on
one key and mark another, and the marker is written only after the apply returns.
`installer_apply_associations` remains the applying half for a topic that needs
it alone; no installer writes its own association loop. A row whose failure mode is `ignore` is best-effort,
because Launch Services does not recognise every identifier on every macOS
version, and only `report` rows are named and counted. Applying a catalog is a run-once
step in every topic that claims file types, so editing a row changes what the
next apply would set without setting it; `DOTFILES_RESET=<topic>-associations dot` applies it.

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
the dependent installer. Setup also names the Homebrew topic, whose installer
runs before the Brewfile rather than with the other topic installers. The
classifier lists every installer and decides none of this order.

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

- Keep `Brewfile` and `mise/config.toml` within the closed literal grammars of
  [ADR-0002](docs/adr/0002-read-declarations-as-closed-literal-grammars.md),
  and preserve their grouping. `_scripts/declared_software.py` is the only
  reader of both files; a consumer reads declarations through it and never
  parses either file itself.
- A trailing comment on a `brew`, `cask`, `mas`, or `[tools]` declaration is
  that entry's catalog description, and the comment above a `cask` block is its
  catalog group. `_scripts/render-software-catalog` renders both into
  `README.md`, so a declaration without one stops the render.
- Put runtimes and language-package CLIs in Mise; put system binaries,
  applications, fonts, MAS apps, and taps in Homebrew.
- A third-party Homebrew formula requires both its tap declaration and a narrow
  trust entry in `homebrew/_bundle.sh`.
- Regenerate `mise/mise.lock` with `mise lock --global` from the repository
  root, in the same change as the declaration. Never edit its versions,
  checksums, or generated structure by hand, and never commit the shape a plain
  `mise install` leaves.
- Interactive upgrades use that generator against staged config and lock
  copies, preserve channels and tool options, and verify that unselected lock
  entries did not change. Publish declarations, lock, and rendered catalog only
  after selected installs succeed and the source snapshot still matches.
- Homebrew reconciliation uses `--no-upgrade`. Only an explicitly confirmed
  selection may request new releases; never use an unqualified `brew upgrade`
  or `mise upgrade` in the maintenance flow.
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
- Do not invent licenses, approvers, support channels, changelogs, or ownership
  beyond Danilo as the sole owner.

## Tests

- Cover behavior changes with isolated fixtures in `tests/`.
- Use temporary homes and fake external commands; never consume real
  credentials, package state, application state, or network services.
- Use the shared `tests/_support/shell-scenario.sh` mechanics: `scenario_run`
  reports each case and tallies, so one failure never hides the cases after it.
  A suite defines an assertion of its own only for vocabulary the harness has
  no business knowing, such as Git refs.
- `tests/documentation_test.sh` is the one exception, and says so in the file:
  it accumulates every undocumented surface and reports them together, because
  listing them one run at a time is the wrong shape for a coverage sweep.
- Name a test after observable behavior, not an implementation detail.
- Assert exit status, stdout/stderr ownership, filesystem state, idempotency,
  and destructive boundaries where relevant.
- A focused test proves its contract only. Run the complete safe suite for
  shared setup, discovery, security, or repository-wide documentation changes.

Fixtures share their stub binaries through `tests/_support/stubs.sh`, which
owns what each faked command does and the one variable that injects its
failure. `shell-scenario.sh` owns how a stub is written; the stub library owns
what it is, so two tests standing in for the same command cannot disagree
about its interface. Add a stub there when a second fixture needs the same
command, and leave a fake in place when it is genuinely specific to one test.

Failure controls use `FAIL_<COMMAND>` or `FAIL_<COMMAND>_<SUBCOMMAND>` for an
exit status. `FAKE_<COMMAND>_<NOUN>` supplies output or simulated state; defaults
are documented beside each stub. For example, `FAIL_DUTI=1` fails assignments,
and `FAKE_DUTI_IDENTIFIERS='.md .rst'` limits that failure to selected rows.
Keep status codes separate from selectors so a fixture declares exactly which
operation fails and how.

`tests/_support/fixture.sh` owns what an installer fixture is: the fake `$HOME`,
the run-once marker directory, and the `fake-bin` first on `PATH`. Build one
with `installer_fixture` and invoke through `fixture_run`, which takes per-run
`KEY=value` overrides before `--`. Pass failure injection that way rather than
exporting it: an `export` before the call and an `unset` after leaks into the
next case whenever something returns between the two.

`tests/_support/jsonc.sh` owns reading tracked JSONC. A second fixture needing
it reads it from there rather than restating it.

### Focused validation matrix

| Change area                                                     | Required focused validation                                                                                  |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Public docs, commands, aliases, dependencies, installer helpers | `tests/documentation_test.sh`                                                                                |
| Setup phases                                                    | `tests/setup_test.sh`                                                                                        |
| Zsh startup or topic shell files                                | `tests/zsh_startup_test.sh` and `zsh -n`                                                                     |
| Topic layout or discovery                                       | `tests/topic_catalog_test.sh`                                                                                |
| Checkout resolution and command adapters                        | `tests/checkout_test.sh`                                                                                     |
| Config and bootstrap links                                      | `tests/link_config_test.sh`, `tests/link_dotfiles_test.sh`                                                   |
| Shared installer helpers                                        | `tests/installer_preamble_test.sh`                                                                           |
| Post-bootstrap checklist                                        | `tests/checklist_test.sh`                                                                                    |
| Generated Markdown tables                                       | `tests/markdown_table_test.sh`                                                                               |
| Generated regions in hand-authored files                        | `tests/generated_region_test.sh`, `tests/generated_renderer_test.sh`                                         |
| Rendered file staleness                                         | `tests/generated_file_test.sh`                                                                               |
| Catalog reading and checking                                    | `tests/catalog_test.sh`                                                                                      |
| Tracked catalog content and rules                               | `tests/catalog_rules_test.sh`                                                                                |
| Declared software reading                                       | `tests/declared_software_test.sh`                                                                            |
| Git helpers                                                     | `tests/git_branch_state_test.sh`                                                                             |
| Tracked Git configuration                                       | `tests/git_config_test.sh`                                                                                   |
| Homebrew                                                        | `tests/homebrew_availability_test.sh`, `tests/homebrew_bundle_test.sh`, `tests/homebrew_maintenance_test.sh` |
| macOS defaults                                                  | `tests/macos_defaults_test.sh`                                                                               |
| SSH and SOPS                                                    | `tests/ssh_provisioning_test.sh`, `tests/sops_provisioning_test.sh`                                          |
| Aider                                                           | `tests/aider_install_test.sh`                                                                                |
| Archiver                                                        | `tests/archiver_install_test.sh`                                                                             |
| Dock layout                                                     | `tests/dock_install_test.sh`                                                                                 |
| Trusted roots and direnv config                                 | `tests/direnv_install_test.sh`                                                                               |
| Coding-agent instructions and settings links                    | `tests/agents_install_test.sh`                                                                               |
| Mise runtimes and lock                                          | `tests/mise_install_test.sh`                                                                                 |
| Interactive upgrades and source preservation                    | `tests/software_upgrades_test.sh`                                                                            |
| Zed JSON and JSONC formatting                                   | `tests/zed_settings_test.sh`                                                                                 |

`_scripts/test` runs every safe suite and returns a single verdict. It discovers
`tests/*_test.sh` and names every suite that failed. A shell loop over the same
files reports only the last suite's status, so run the module rather than the
loop:

```bash
_scripts/test
```

Pass a pattern to run one row of the matrix above:

```bash
_scripts/test link_config
```

Run applicable static checks:

```bash
git grep -IlzE '^#!.*(bin/sh|bash)([[:space:]]|$)' -- ':!*.md' ':!.agents/' \
  | xargs -0 shellcheck
git grep -IlzE '^#!.*(bin/sh|bash)([[:space:]]|$)' -- ':!*.md' ':!.agents/' \
  | xargs -0 shfmt -d -i 2 -ci -bn
git ls-files -z -- '*.zsh' | xargs -0 -n1 zsh -n
while IFS= read -r -d '' markdown_path; do
  [ ! -f "$markdown_path" ] || mdformat --check "$markdown_path"
done < <(
  git ls-files -z --cached --others --exclude-standard -- '*.md' ':!.agents/'
)
git diff --check
```

`zsh -n` reads one script and treats any further path as that script's
argument, so each file needs its own invocation. The agent skills under
`.agents/` are upstream payloads recorded in `skills-lock.json`; the checks
skip them rather than reformat what the next skills update would restore.

`.github/workflows/ci.yml` runs the same checks and `_scripts/test` on macOS for
every pull request and every push to `main`. Change the two together. Its check
tools consume the repository's Mise lock, formatter extras have explicit pins,
actions use full commit SHAs, and the runner uses a named macOS major. The
hosted image and transitive language-package dependencies are not immutable.

All applicable formatters, linters, and tests must finish without errors or
warnings introduced by the change.

## Security and destructive boundaries

- Secrets belong in gitignored `.localrc` with mode `600` or an appropriate
  system credential store.
- Never log or commit Git identity, SSH private keys, SOPS identities,
  kubeconfigs, auth stores, or account identifiers.
- SSH and SOPS installers may repair directories, links, and permissions; only
  the explicit `ssh-key-create` and `sops-key-create` commands create keys.
- Tracked Zed, OpenCode, Claude Code, Conductor and Kimi Code configuration
  must not contain plaintext credentials or fake interpolation for settings that
  treat `$VARIABLE` literally.
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
