---
status: accepted
---

# Each entry point resolves the checkout that contains it

A command acts on the checkout that contains it, which need not be the active
checkout. Every entry point resolves that checkout in its own prologue, with the
one-line idiom of its shell, following symbolic links to get there. No shared
resolver answers the question and no inherited `DOTFILES_ROOT` overrides it.

## Considered options

A shared resolver looks like the cure for the repeated prologue. A shell file
cannot source what it has not located, so every caller has already found its
checkout to reach the resolver, which then derives the same directory again.
Following a symlinked file, its one real task, belongs to the only entry point
reached that way: `~/.zshrc`.

Honouring an inherited `DOTFILES_ROOT` lets a script run from a worktree act on
the active checkout, because every shell started through `~/.zshrc` exports the
active checkout's root.

A link in the home directory that records the checkout points at a worktree
that can disappear, and shell startup then fails.

## Consequences

The prologue stays repeated in every entry point on purpose. Tests give each
shell's idiom one case with a misleading inherited `DOTFILES_ROOT`, and a
static check rejects a command that reads an inherited value.
