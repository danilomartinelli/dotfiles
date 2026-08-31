# A retired link is not the linker's question

`mise/install.sh` keeps its own readlink comparison for the two legacy paths it
retires, `~/.mise.toml` and `~/.mise.lock`. It looks like the target
classification the config linker owns, and it stays where it is.

## Considered options

Routing it through `link-config --status` was the obvious cleanup, and it is why
this file exists: the two look identical and answer different questions.

`--status` classifies a target against a **live** source. `link_is_current`
resolves both halves and compares them, and the script refuses before any of
that with `source not found` when the source is absent. The sources these two
links point at — `mise/mise.toml.symlink` and `mise/mise.lock.symlink` — were
deleted when the topic moved to `$HOME/.config/mise`. Their absence is the whole
reason the links are legacy, so the one input `--status` requires is the one
input this case cannot supply. Asking it anyway returns exit 2 and no word, and
the retirement silently stops happening.

Teaching `--status` to classify against a missing source would fix that for one
caller. Nothing else asks: every other consumer classifies a target it is about
to link, so its source exists by construction. By the rule this repository
applies elsewhere, one adapter is a hypothetical seam, and this one would widen
the interface of the module every linking topic depends on to serve a question
only a migration asks.

The comparison is also narrower than the linker's. It removes a path only when
it points at this topic's own former source; the linker's classification feeds
policies that back up, preserve, or destroy. Sharing the arithmetic would not
share the guarantee.

## Consequences

`mise/install.sh` carries about twenty lines that resemble
`_scripts/link-config:179-191`, and a reader comparing the two will keep noticing
it. The duplication is bounded: it disappears entirely when the two legacy links
are old enough to stop retiring, which is the point at which `remove_legacy_link`
and both of its call sites are deleted rather than refactored.

Nothing else in this repository may copy that arithmetic. A topic classifying a
target whose source exists calls the linker; `aider/install.sh` was the other
site that had not, and no longer does.
