# Git identity setup stays in the orchestrator

`setup_gitconfig` in `_scripts/setup` knows `git/gitconfig.local.symlink`, its
`.example` sibling, the three placeholder tokens, and the osxkeychain-versus-
cache rule, while `git/install.sh` exists and holds none of it. It looks
misplaced and it stays where it is.

## Considered options

Moving the whole thing into `git/install.sh` does not work: it prompts, and a
topic installer is non-interactive by contract, so `dot` would block on a
question during an unattended run.

Splitting it — setup keeps the prompting, the git topic gains a renderer taking
the two answers — is the version that survives that objection, and it is the one
this records a no to. The renderer would have exactly one caller, now and
plausibly forever, because nothing else renders a gitconfig. By the rule this
repository already applies elsewhere, one adapter is a hypothetical seam.
Knowledge would move rather than concentrate: setup would still have to know the
renderer's path and the order of its arguments, so a local function becomes a
cross-module call and the placeholder tokens end up named in two files instead
of one.

## Consequences

`escape_sed_replacement` stays in `_scripts/setup` with its single caller, and
the 31 lines of git knowledge stay with the prompt that produces them.

The friction that surfaced this is real and is a different problem: `setup` has
no seam for observing what ran, so `tests/setup_test.sh` falls back to `awk` and
`grep` over the module's own source text to assert that `run_bootstrap` opens no
apps. Moving `setup_gitconfig` would not have improved that by one line. Giving
`setup` an observable seam would, and that is the change to scope if this area
is reopened.
