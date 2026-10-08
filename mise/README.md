# Mise maintenance

`_scripts/mise-policy` owns configuration selection, trust, and lock policy.
Every caller passes its own resolved checkout; the module never discovers one
from the current directory or an inherited `DOTFILES_ROOT`.

The installer links `config.toml` and `mise.lock` into `~/.config/mise`. It also
asks the config linker to remove legacy `~/.mise.toml` and `~/.mise.lock` links
only when they point to this checkout's retired `mise/*.symlink` sources.
Those sources need not still exist. Local files and links to other sources are
preserved.

## Post-install reconciliation

After a successful locked installation, `install.sh` calls
`sh "$TOPIC_DIR/_post-install.sh"`. This private executable takes no arguments
and resolves its own checkout. It reconciles formatter plugins, prunes unused
tool versions, runs the Claude Code package postinstall, and repairs the
OpenCode native executable, in that order.

`_post-install.sh` owns package discovery, repair choices, ordering, and failure
propagation. The caller observes its exit status and normal installer output;
warnings do not imply a failing status. Tests use that same interface without
first linking configuration or installing every declared tool.

Configuration links, persistent trust, legacy-link retirement, and the initial
locked installation remain in the installer. `_scripts/mise-policy` retains
Mise invocation policy, and `_extras.py` retains formatter-pin interpretation
and refresh verification. The controlled upgrade continues to invoke the full
installer after publishing sources; subsequent installer failures do not roll
back that publication, as specified by
[ADR-0007](../docs/adr/0007-isolate-upgrade-effects-and-source-publication.md).

The extraction preserves current outcomes, including their asymmetry:

| Condition                                                                           | Outcome                              |
| ----------------------------------------------------------------------------------- | ------------------------------------ |
| Package lookup fails or returns no directory                                        | Skip that package's step silently    |
| Formatter reconciliation fails                                                      | Stop before pruning or agent repairs |
| Pruning fails                                                                       | Discard its output and continue      |
| Claude's package installer is missing                                               | Skip the Claude step                 |
| Claude's package installer fails                                                    | Warn and continue to OpenCode        |
| Either OpenCode file is missing, or the destination is already identified as Mach-O | Skip the repair                      |
| OpenCode hard link fails                                                            | Try copying the native binary        |
| Both OpenCode hard link and copy fail                                               | Warn and continue                    |
| Making the repaired OpenCode executable fails                                       | Stop with a nonzero status           |

Each run invokes Claude's package installer when present; its own script owns
the repeated-run behavior. OpenCode accepts an existing Mach-O destination
without checking its version, architecture, or executable permission. An
unsuccessful file-type probe enters the repair path when both files exist.
Preserving behavior also preserves the existing repair mechanism and diagnostics;
the extraction adds no rollback or stronger integrity guarantee.

`tests/mise_post_install_test.sh` invokes the same private entrypoint as the
installer, using temporary package directories and fake external commands.
It covers the outcomes above, execution order, successful and repeated repairs,
and the copy fallback. Its formatter scenarios run the real `_extras.py` against
a fixture environment. `mise_install` retains installer composition coverage,
and `software_upgrades` retains the test for failures after source publication.
Run these suites and `mise_extras` when changing this path, followed by the
complete safe suite for changes to shared installation behavior.

## Interface

```text
mise-policy <checkout> [--declarations <directory>] run <command> [arguments...]
mise-policy <checkout> [--declarations <directory>] lock [--bump] <tools...>
mise-policy <checkout> {shell|completion|ci|local|trust}
```

`run` supports the maintenance commands `install`, `exec`, `where`, `ls`,
`outdated`, and `prune`. It selects only the supplied checkout's `mise/config.toml`
and `mise/mise.lock`, ignores inherited version selectors and external
configuration, and runs from the checkout with lock reading enabled and writes
disabled. Missing or incompatible resolutions fail; installation does not fall
back to a new release. Other inherited environment, including package-manager
credentials and installation/cache locations, remains available to subprocesses.

`--declarations` selects a separate directory containing staged `config.toml`
and `mise.lock` copies. It does not change where the module finds the checkout's
helpers. Trust includes every root from `_scripts/trusted-roots`, plus the staged
directory only for that invocation.

`lock` requires an explicit tool selection and invokes Mise's global lock
generator against those declarations. It alone disables locked mode. The
controlled upgrade owns selection, validation of unselected entries, source
concurrency checks, and publication of staged files; the module does not select
releases or publish changes. Manual regeneration uses the same operation.

The remaining operations emit configuration without installing tools:

| Operation    | Output and consumer                                                  |
| ------------ | -------------------------------------------------------------------- |
| `shell`      | Complete Zsh activation and trust assignments for `mise.zsh`         |
| `completion` | Zsh completions, applied only after successful activation            |
| `ci`         | Environment assignments written to `GITHUB_ENV` before `mise-action` |
| `local`      | Canonical root `.mise.toml`, held to this output by a contract test  |
| `trust`      | Persistent trust TOML, linked by `_configure-trust.sh`               |

Shell preparation preserves personal configuration overrides and normal project
discovery. It removes the legacy default `MISE_GLOBAL_CONFIG_FILE` selector
that bypassed `conf.d`. Failed preparation or activation discards the generated
payload, reports a diagnostic, and leaves the shell usable with its previous
environment. Completion is skipped after failed activation.

## Lock boundary and validation

The root `.mise.toml` requires ordinary execution inside the checkout to consume
recorded resolutions and leave the lock unchanged, including when Mise installs
a missing tool. It contains only local policy, not a duplicate tool catalog.
Regenerate its contents with `_scripts/mise-policy "$PWD" local > .mise.toml`.

The global lock is linked to the active checkout's lock. Ordinary commands
outside the checkout do not load this local protection and can rewrite that
same file. This accepted boundary is recorded in
[ADR-0006](../docs/adr/0006-own-mise-policy-without-changing-project-behavior.md).

`_scripts/test` uses the shared fake in `tests/_support/mise.py` for both shell
and Python callers. An additional opt-in characterization uses a real Mise
binary with a temporary home, data/cache/state directories, and a local plugin
that installs only a tiny fixture executable:

```bash
python3 -B tests/_support/mise-characterization.py /absolute/path/to/mise
```

Run it when changing the Mise version or its policy. It covers a missing tool,
missing/incompatible lock resolutions, the external write boundary, foreign
configuration, CI environment, and staged regeneration without using personal
configuration or installing software into the real home.
