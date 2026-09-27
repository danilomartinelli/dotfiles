# dot installs what the Mise lock records

`mise/install.sh` runs `mise install --locked`. An update run installs the
versions `mise/mise.lock` records and never writes the file. `mise lock --global`
from the checkout is the one command that does, in the same change as the
declaration it follows.

## Considered options

A plain `mise install` was the installer's step, and it writes the lock. It
does not write what `mise lock --global` writes: the lock resolves an Erlang
variant for the Linux glibc platforms carrying `precompiled_os`, and an install
on this Mac strips it again; the lock records Elixir's macOS archive by
`sha256`, and an install rewrites it as `blake3`. Neither command is wrong about
its own output, so whichever ran last won. The Erlang variant entered or left
the file in seventeen commits between August and September 2026 — `2de62897`
added it, `fc48b243` removed it, `b7d2232e` added it, `0c7e48ce` removed it,
and `2428d753`, `c0bd0c25` and `a5de6f8c` repeated the cycle — and every `dot`
after a lock refresh left the tree dirty.

Committing the install shape and forbidding `mise lock --global` was the
previous answer. It held until the next person advanced a version, because
advancing one without the lock command means editing the file by hand.

Restricting `lockfile_platforms` to `macos-arm64` would remove the Erlang
variant, but not the Elixir checksum, and a lock that already lists a platform
keeps it, so the file could only reach that shape by being deleted and
regenerated. The current Mise refuses that regeneration: dependency locking does
not support `uvx_args`, which `pipx:aider-chat` and `pipx:mdformat` declare.

Setting `locked = true` in `mise/config.toml` would make every global install
strict, not only this one. Mise documents that locked mode fails even a
read-only lookup for a version the lock lacks, installed or not, so a
declaration edited before its lock would reach every shell rather than one
`dot` run.

## Consequences

A declaration changed without its lock now stops `dot` at the Mise topic, and
the error names `mise lock --global`. That is the failure the lock exists to
catch: before, the install resolved the change silently and the lock drifted
from what had been reviewed.

A plain `mise install` or `mise upgrade` typed in a shell still rewrites the
lock in its own shape. That is not a run this repository owns;
`mise lock --global` settles the file again. The `mi` alias stays a plain
install because a project without a lock cannot install in locked mode.
