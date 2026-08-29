# One reset variable for run-once steps

`DOTFILES_RESET` names the run-once steps to re-arm, as a space-separated list
of topic keys or the word `all`. It is the only way to make a run-once step
apply again without deleting its marker by hand, and no topic defines a reset
variable of its own.

## Considered options

The Dock and Zed installers each grew their own protocol. The Dock honoured
`DOTFILES_DOCK_RESET=1`; Zed had no variable at all and told you to delete the
marker file. Preserving both spellings would have re-created that divergence
inside the shared helper, since the escape hatch would have to be optional.

Deriving a per-topic variable from the marker key — `dock` to
`DOTFILES_DOCK_RESET` — keeps the Dock's existing spelling working, and was the
first choice. POSIX `sh` has no indirect expansion, so reading a derived name
requires `eval "value=\${$name:-}"`, with the `:-` load-bearing under `set -u`.
That put the subtlest line in the repository inside the module every installer
sources, to preserve one variable name that one person types.

A single variable needs no derivation, no `eval`, and no per-topic naming rule.
Matching it is a space-padded `case` against `${DOTFILES_RESET:-}`, which is
`set -u`-safe by construction and readable without knowing a convention.

## Consequences

`DOTFILES_DOCK_RESET` no longer works, and `README.md` documents the
replacement. Every run-once step added later inherits the variable instead of
inventing a name, which is what #27 depends on when the Dock layout becomes a
catalog.

The keys are a user-facing contract: renaming a run-once key silently breaks the
reset command for that step, so keys change only with the README.
