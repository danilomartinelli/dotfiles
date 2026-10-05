---
status: accepted
---

# Read declarations as closed literal grammars

The Brewfile is Ruby that Homebrew evaluates and `mise/config.toml` is TOML that
Mise reads, while the repository's own readers parsed both literally, each by
its own rules; they agreed only because the files happened to stay simple.
Declared software is read by one module that accepts a closed literal shape for
each file and fails on any other line:

- Brewfile: literal `tap`, `brew`, `cask`, `mas` and `cask_args` lines,
  comments and blank lines. Homebrew is no longer asked (`brew bundle list`)
  which formulae and casks exist.
- `mise/config.toml`: one declaration per line in `[tools]`, whose value is a
  version string or an inline table with a version string.

Reading declarations stays a pure file read that every consumer, the controlled
upgrade included, shares and tests without a package-manager fake. A rejected
line signals that a package manager and the repository could disagree, or that a
version rewrite could not stay on one line.

## Consequences

Brewfile conditionals, loops and entry options such as `args:`, and Mise version
lists, sub-tables and multi-line tables, cannot be used until the module learns
them.
