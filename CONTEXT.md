# Domain glossary

Vocabulary for this macOS dotfiles checkout. Prefer these names in architecture
discussion and agent work.

## Checkout and adapters

- **Checkout root** — Physical directory of the invoking Git worktree / archive that contains the tracked files. Resolved by `dotfiles-root.symlink`.
- **Adapter checkout** — Shared preamble (`_scripts/adapter-checkout.sh`) that public adapters source to export `DOTFILES_ROOT` (prefer `~/.dotfiles-root`, else sibling resolver).
- **Public adapter** — Thin executable in `bin/` or `_scripts/bootstrap` that resolves the checkout and delegates to a deeper module.

## Topics and linking

- **Topic** — Visible top-level tool/config folder discovered by `topic-catalog`.
- **Topic catalog** — Private classifier (`_scripts/topic-catalog`) emitting kind/path records for setup, Zsh startup, and docs tests.
- **Installer preamble** — Shared private module (`_scripts/installer-preamble.sh`) that topic `install.sh` scripts source to export `TOPIC_DIR` / `DOTFILES_ROOT`, skip non-Darwin platforms, wrap `link-config`, and emit the inner `›` / `✓` / `→` / `Warning:` vocabulary.
- **Link-config** — Non-interactive config linker (`_scripts/link-config`) with policies `replace-with-backup`, `preserve-existing`, and `numbered-backup`.
- **Link-dotfiles** — Bootstrap home linker (`_scripts/link-dotfiles`) for `.localrc` and topic `*.symlink` files (interactive or `--batch`).

## Homebrew and macOS

- **Homebrew availability** — Module that finds `brew` / prefix (`homebrew/_availability.sh`).
- **Homebrew bundle** — Module that trusts declared third-party taps and runs `brew bundle` (`homebrew/_bundle.sh`).
- **Defaults catalog** — Tab-separated macOS preference data (`_macos/defaults.tsv`) applied by `set-defaults.sh`.

## Git

- **Branch state** — Shared Git worktree/branch queries (`git/_branch-state.sh`) used by `git-*` adapters and the prompt.
