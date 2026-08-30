# Checkout resolution has two spellings on purpose

`_scripts/adapter-checkout.sh` resolves the checkout through
`dotfiles-root.symlink`, following symlink hops and preferring the installed
`~/.dotfiles-root`. `_scripts/installer-preamble.sh` resolves it as
`$(dirname "$0")/..` and consults no resolver. Both are correct for their
callers, and unifying them buys nothing.

## Considered options

Routing the preamble through the resolver was the obvious cleanup, and it is
why this file exists: the two spellings look like drift and are answers to two
different questions.

A `bin/` adapter is reached through `PATH`, so `$0` may be a symlink, a bare
command name, or a path relative to any working directory. Resolving it needs
the hop-following the resolver does. A topic installer is always
`<checkout>/<topic>/install.sh`, invoked by `_scripts/setup` at that path, so
`$0/..` is the checkout by construction — including inside a linked worktree,
where the resolver would agree. There is no input on which the two differ.

Routing `_scripts/setup`, `_scripts/link-dotfiles`, and `_scripts/checklist`
through `adapter-checkout.sh` was the narrower version, and it fails for a
different reason. Those three are invoked by real path too, and the last two
short-circuit on an inherited `DOTFILES_ROOT` so that a `setup` run does not
re-resolve for every child. Preserving that guard around a sourced resolver
makes each of them longer than the four lines it replaces, and `setup` still
needs the resolver's own path for `--install`.

The prologue itself — the `cd -P` expression 39 files carry to reach either
module — is not removable. A shell file cannot source what it has not located,
so every candidate replacement is a different spelling of the same one line.

## Consequences

Two resolution modules stay, and `CODING_STANDARDS.md` says which one a new
file uses: a `bin/` adapter or a `*.zsh` startup file takes
`adapter-checkout.sh`, a topic installer takes the preamble.

`_scripts/test-checkout-root` covers the resolver, and
`tests/installer_preamble_test.sh` covers the preamble's resolution. Neither
grows a case for the other.
