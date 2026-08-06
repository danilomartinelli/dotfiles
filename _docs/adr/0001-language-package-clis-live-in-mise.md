# Language-package CLIs live in Mise, not Homebrew

The repository declares tools in two places (`Brewfile` and
`mise/mise.toml.symlink`) and historically split language-distributed CLIs
arbitrarily between them (`wrangler` and `aider` via Homebrew, `eas-cli` and
`mdformat` via Mise). We decided on one rule: CLIs distributed as language
packages (npm, PyPI, gem, Go modules) are declared in `mise/mise.toml.symlink`
using the matching backend (`npm:`, `pipx:`, `gem:`, `go:`); system binaries,
libraries, and casks stay in the `Brewfile`. Mise pins exact versions and
already owns the language runtimes these packages run on, so this keeps one
version regime per ecosystem and avoids Homebrew vendoring duplicate
interpreters. The alternative — "everything Homebrew packages goes in
Homebrew" — was rejected because it perpetuated the ambiguity and ties CLI
versions to formula update cadence.

One deliberate exception: this repository's own quality toolchain
(formatters and linters — `shfmt`, `mdformat`, `shellcheck`) lives in Mise
regardless of how it is packaged, so the whole lint/format regime is pinned
by the same lockfile.
