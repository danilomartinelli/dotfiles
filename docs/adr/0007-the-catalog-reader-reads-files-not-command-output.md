# The catalog reader reads files, not command output

`catalog_each_row` takes a path. A catalog that arrives as a command's stdout —
the classification `_scripts/topic-catalog` emits — is read by its consumer
directly, and that is not a gap to close later.

Rows arrive on file descriptor 3 so a handler may run `duti`, `dockutil`, or
`ocx` without those commands consuming the rows still to be read. That property
is the module's entire reason to exist. Accepting the catalog on stdin would
surrender it for every consumer, to serve the consumers that have no handler
running anything.

## Considered options

Teaching the reader to accept `-` for stdin was the obvious way to make one
rule cover every catalog, and it is why this file exists: the rule it would
satisfy is one this repository stated more absolutely than the code can support.
`AGENTS.md` said "no consumer writes its own `read` loop", and three consumers
did — `_scripts/setup`, `_scripts/link-dotfiles`, and `zsh/_startup.zsh` — each
reading `topic-catalog` output. They were not drift. They read a different
shape.

Having those three write the classification to a temporary file first would let
them call the reader, at the cost of a temporary file per shell startup, and
`zsh/_startup.zsh` exists to avoid exactly that kind of per-shell work. It also
buys nothing: none of the three runs a handler that touches stdin, so the
hazard the reader guards against cannot reach them.

Widening the reader was the change worth making, and it is separate. It read
four columns while `opencode/profiles/_routing.tsv` declares seven, so the
repository's widest catalog had grown three parsers of its own inside
`_scripts/render-opencode-profiles`: a Bash array split for validation, an
`awk` pass for the per-profile roles, and a `jq` split that addressed the
columns by integer index. The reader now delivers seven and the validation
reads through it.

## Consequences

A catalog wider than seven columns packs its trailing columns into the last
argument rather than being refused, so widening a catalog past seven means
widening the reader first. `tests/catalog_test.sh` pins that behavior so the
limit is a stated one rather than a surprise.

The `jq` pass in `render-opencode-profiles` still splits the routing table
itself, because it consumes the whole table at once to compose one JSON
document rather than acting per row. It is the one parser the shared reader
cannot replace, and it is the reason the column *positions* remain a fact
stated in two places.

`AGENTS.md` now names the case its rule governs — a tab-separated catalog file —
instead of every list in the repository.
