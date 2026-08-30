# The Git executable is a parameter, not module state

Every function in `git/_branch-state.sh` takes the Git executable as its first
argument, and all 27 call sites across `bin/git-*` and `zsh/prompt.zsh` spell
it. That repetition is the seam, not a leak through it.

## Considered options

Binding the executable once — a `DOTFILES_GIT` set where the module is sourced,
read by every function — is the obvious way to drop an argument from 27 places,
and it is why this file exists: it looks like the interface shrinking and is
actually the module's central guarantee being given up.

The module is sourced into the interactive Zsh session by `zsh/prompt.zsh`,
which is why its function bodies are subshells: sourcing it must not leave
variables behind in a person's shell. A module-level variable is exactly that
leftover, in the one consumer that runs on every prompt render.

The two consumers also disagree about what the executable is, deliberately.
A `bin/git-*` adapter wants whatever `git` resolves to on `PATH`. The prompt
resolves `$commands[git]` once, falling back to `/usr/bin/git`, because it
re-renders constantly and a `PATH` walk per render is a cost it declines to
pay. One bound value cannot serve both without the prompt losing its
resolution or the adapters gaining one they do not want.

Passing the executable also keeps the seam reachable from a test without any
environment setup: `tests/git_branch_state_test.sh` hands each function a fake
and reads what it was called with. That is two real adapters across the seam,
which is what justifies having one.

## Consequences

A new Git adapter passes `git` to every branch-state call, and a reviewer
counting repetition will keep finding 27 of them. The argument stays.

A future consumer needing a third resolution adds a caller, not a variable. If
one ever does need module state, `zsh/prompt.zsh` is the constraint to check
first: whatever is introduced has to survive being sourced into a login shell.
