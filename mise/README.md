# Mise maintenance

`_scripts/mise-policy` owns configuration selection, trust, and lock policy.
Every caller passes its own resolved checkout; the module never discovers one
from the current directory or an inherited `DOTFILES_ROOT`.

The installer links `config.toml` and `mise.lock` into `~/.config/mise`. It also
asks the config linker to remove legacy `~/.mise.toml` and `~/.mise.lock` links
only when they point to this checkout's retired `mise/*.symlink` sources.
Those sources need not still exist. Local files and links to other sources are
preserved.

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
