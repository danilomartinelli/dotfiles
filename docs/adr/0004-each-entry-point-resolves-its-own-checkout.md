---
status: accepted
---

# Each entry point resolves the checkout that contains it

A command acts on the checkout that contains it, which need not be the active
checkout. Every entry point resolves that checkout in its own prologue, with the
one-line idiom of its shell, following symbolic links to get there. No shared
resolver answers the question, no inherited `DOTFILES_ROOT` overrides it, and no
`~/.dotfiles-root` link records it.

## Considered options

A shared resolver, `dotfiles-root.symlink` behind `_scripts/adapter-checkout.sh`,
looked like the cure for the repeated prologue. A shell file cannot source what
it has not located, so every caller had already found its checkout to reach the
resolver, which then derived the same directory again. Its interface was as
large as the line it replaced. Its one real task, following a symlinked file,
belongs to the only entry point reached that way: `~/.zshrc`.

Honouring an inherited `DOTFILES_ROOT` let a script run from a worktree act on
the active checkout, because every shell started through `~/.zshrc` exports the
active checkout's root. No caller ever named a checkout other than the script's
own.

The `~/.dotfiles-root` link never changed an answer and nothing outside the
repository read it. An update run from a worktree pointed it at a directory
that disappeared with the worktree, and shell startup then failed.

## Consequences

The prologue stays repeated in every entry point on purpose. Tests give each
shell's idiom one case with a misleading inherited `DOTFILES_ROOT`, and a
static check rejects a command that reads an inherited value. A machine set up
before this decision keeps a `~/.dotfiles-root` that nothing reads; remove it by
hand.
