# A link the linker could not make is a failure

`replace-with-backup` owns exactly one backup slot. When `<target>.backup` is
already occupied, the config linker cannot honour the policy without destroying
the earlier backup, so it now exits 1 instead of warning and exiting 0.

## Considered options

Warning and exiting 0 was the previous behaviour, and it reads defensibly: the
linker preserved both files and said so on stderr. What it also did was tell
every caller the link existed. `_scripts/link-dotfiles:179` ends in
`|| return 1`, which could never fire; `_scripts/setup` then printed
`[ OK ] dotfile links` for a run in which a tracked dotfile was never linked.
The one caller positioned to notice was the one the exit status lied to.

Reporting the outcome as a word on stdout — the way `--status` reports a target
classification — was the other option, and it is the shape the classification
half already uses. The acting path cannot borrow it: stdout carries the prose a
person reads under the installer's banner, and `installer_link_config` passes
that straight through to the terminal. Adding a machine-readable word to the
same stream would either displace the prose or force every caller to filter it.

Exit status 2 would have matched the sibling refusals at `replace-generated`,
which already spell "I will not remove this" that way. `CODING_STANDARDS.md`
reserves 2 for invalid CLI usage, and this is valid usage under a valid policy
that the filesystem made impossible. 1 is the operational failure, and it makes
`link-dotfiles`'s existing `|| return 1` correct without a mapping table.

## Consequences

A topic installer whose linked target has a stale `.backup` sibling now stops
instead of continuing. That is reachable through `installer_link_tool_config`,
which takes the default policy, so a `~/.config/<tool>/<file>.backup` left
behind by an earlier run will fail that topic until it is moved or removed. The
error names both paths and the remedy, because the installer stops at the point
a person has to act.

`preserve-existing` still exits 0 without linking, and that stays correct: the
caller asked for the target to be kept, so keeping it is the request being
honoured rather than refused.
