---
status: accepted
---

# Read declarations as closed literal grammars

Homebrew evaluates the Brewfile as Ruby and Mise reads `mise/config.toml` as
TOML, while this repository reads both literally. One module,
`_scripts/declared_software.py`, reads declared software, accepts a closed
literal shape for each file and fails on any other line:

- Brewfile: literal `tap`, `brew`, `cask`, `mas` and `cask_args` lines,
  comments and blank lines.
- `mise/config.toml`: one declaration per line in `[tools]`, whose value is a
  version string or an inline table with a version string.

Reading declarations stays a pure file read that every consumer, the controlled
upgrade included, shares and tests without a package-manager fake; Homebrew is
not asked which formulae and casks exist. A rejected line signals that a
package manager and the repository could disagree, or that a version rewrite
could not stay on one line.

## Consequences

Brewfile conditionals, loops and entry options such as `args:`, and Mise version
lists, sub-tables and multi-line tables, cannot be used until the module learns
them.
