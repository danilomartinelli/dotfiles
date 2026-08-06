# Zsh startup memoizes the topic catalog by directory mtime

`_scripts/topic-catalog` is the single interface that classifies the
repository layout, but invoking it on every interactive shell cost ~250 ms —
roughly three quarters of total startup. We decided to memoize its output in
`$XDG_CACHE_HOME/dotfiles/`, keyed by checkout path so parallel worktrees
never collide. Invalidation is correct by construction: the catalog's output
only changes when files are added, removed, or renamed, and those operations
always bump the mtime of the checkout root or a first-level directory, which
startup compares against the cache with plain `stat` checks (~1 ms). The
classifier remains the sole source of truth — the cache is a transparent
memo, regenerated on any mismatch, and cache writes are best-effort so a
read-only cache directory cannot break startup. The alternative of generating
the cache during `dot`/setup was rejected because it leaves a window where a
manual file addition desynchronizes the shell until the next update run.
