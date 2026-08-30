# The topic-catalog cache watches directories, not content

Zsh startup memoizes `_scripts/topic-catalog` output under
`$XDG_CACHE_HOME/dotfiles/`, and treats that cache as stale only when
`$DOTFILES_ROOT` or one of its direct children has a newer mtime. Editing the
contents of a `.zsh` file therefore never invalidates the cache, which is
correct: the catalog classifies files by name and location, so only adding,
removing, or renaming one can change it, and every such change bumps the
containing directory's mtime.

## Considered options

Hashing the classified file list into the cache key was the obvious
alternative, and it is what the cache is a cheaper version of. Producing that
hash means running the classifier, which is the work the cache exists to avoid;
paying it on every shell to discover that nothing changed is the whole cost
back.

Watching every topic directory recursively rather than only the checkout root
and its direct children would catch a rename nested two levels deep, such as
`alpha/_private/nested.zsh`. `topic-catalog` excludes underscore- and
dot-prefixed paths at every level and prunes `*.symlink` directories, and no
classified record lives more than one directory below a topic, so the deeper
walk would cost a `stat` per directory on every shell to find changes that
cannot alter the output.

## Consequences

The cache key embeds the checkout path with `/` replaced by `%`, so parallel
worktrees never share an entry and a moved checkout starts cold rather than
reading a stale neighbour's catalog.

Cache writes are best-effort. A read-only or unwritable
`XDG_CACHE_HOME` makes every shell reclassify, which is slower and still
correct; it never fails startup.

Touching a topic directory without changing its contents re-runs the
classifier. That is the safe direction of the trade, and it is why
`_scripts/topic-catalog` remains the single owner of classification: the cache
never decides what a file is, only whether the answer can be reused.
