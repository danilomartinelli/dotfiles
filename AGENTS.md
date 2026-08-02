# AGENTS.md

This file provides guidance to code assistants when working with code in this repository.

## Repository Overview

This is a personal macOS dotfiles repository for JavaScript/TypeScript and DevOps development. It follows a topic-based architecture where each tool/topic has its own directory with standardized file patterns for configuration, installation, and shell integration.

## Common Commands

### Initial Setup

```bash
# First-time installation
_scripts/bootstrap

# This will:
# - Prompt for git config (name/email)
# - Create symlinks for all *.symlink files to ~
# - Install Homebrew and all dependencies from Brewfile
# - Configure macOS defaults
# - Set up ~/.localrc from template
```

### Daily Usage

```bash
# Refresh the checkout, update Homebrew, and run topic installers
bin/dot
# or after first run:
dot

# Edit dotfiles in $EDITOR
dot --edit
```

### Manual Updates

```bash
# Update Homebrew packages only
brew update && brew upgrade

# Re-run bootstrap (re-symlink configs)
_scripts/bootstrap
```

### Testing & Validation

```bash
# Test setup orchestration in isolated temporary fixtures
tests/setup_test.sh

# Test deterministic Zsh startup in an isolated temporary HOME
tests/zsh_startup_test.sh

# Reload shell configuration (after making changes)
source ~/.zshrc
# or use alias:
reload!

# Test shell functions
c <tab>              # Test project directory autocomplete
extract file.zip     # Test archive extraction

# Test checkout-root resolution, worktrees, and its startup seam
_scripts/test-checkout-root
```

## Architecture & Code Structure

### Topic-Based Organization

The repository uses a **topic directory pattern** where each tool/topic (git, docker, zsh, etc.) has its own directory with standardized filenames:

```
topic/
├── install.sh       # Runs during canonical setup dependency phases (optional)
├── *.symlink        # Auto-linked to ~ (e.g., config.symlink → ~/.config)
├── path.zsh         # PATH modifications (loaded first)
├── aliases.zsh      # Command aliases
├── env.zsh          # Environment variables
├── completion.zsh   # Shell completions (loaded last)
└── *.zsh           # Other shell configs (auto-loaded)
```

**Critical Architecture Rules:**

- Folders starting with `_` are completely ignored (e.g., `_scripts/`, `_macos/`)
- Files starting with `_` are ignored even in regular topic folders
- Standard filenames must be exact: `path.zsh`, `aliases.zsh`, `completion.zsh`, `install.sh`
- Only `.symlink` files are automatically symlinked to home directory

### Shell Loading Sequence

`zsh/zshrc.symlink` resolves the active checkout, exports `$DOTFILES_ROOT`, and
sources the private `zsh/_startup.zsh` module exactly once. The module loads
configuration in this precise order:

1. **Environment setup**: Sets `$PROJECTS` (`~/Code`), then sources optional `~/.localrc` and `.commonrc`
2. **Baseline paths**: Discovers and exports `$HOMEBREW_PREFIX` once, then initializes de-duplicated PATH, MANPATH, functions, and fpath
3. **PATH files**: Sources sorted `*/path.zsh` files from non-ignored topics
4. **Main configs**: Sources sorted topic `*.zsh` files except path, completion, and `zsh/prompt.zsh`
5. **Custom prompt**: Sources `zsh/prompt.zsh` as the sole prompt implementation
6. **Completions init**: Runs `compinit` once
7. **Completion files**: Sources sorted `*/completion.zsh` files
8. **Syntax highlighting**: Sources the optional Homebrew script last

Topic discovery excludes every `_`-prefixed directory and file, including
`zsh/_startup.zsh`. Loader-only `_dotfiles_*` variables are removed after each
startup pass, and reloading `.zshrc` keeps PATH, fpath, and hooks de-duplicated.

### Key Scripts

**`_scripts/setup`** (canonical setup module):

- Exposes `bootstrap` and `update` modes to the command adapters
- Uses the checkout root resolved by `dotfiles-root.symlink`
- Installs or repairs the `~/.dotfiles-root` seam during updates
- Owns phase order, failure policy, Homebrew setup, and topic discovery
- Executes only sorted top-level `topic/install.sh` files and excludes reserved `_` topics
- Stops on required setup failures while treating checkout/package refreshes and hostname normalization as advisory

**`_scripts/bootstrap`** (first-time adapter):

- Prompts for git author name/email
- Creates `git/gitconfig.local.symlink` from template
- Symlinks all `*.symlink` files to home directory
- Installs `dotfiles-root.symlink` as `~/.dotfiles-root`
- Creates `~/.localrc` from `.localrc.example`
- Applies macOS defaults and normalizes the hostname
- Installs Homebrew, Brewfile dependencies, and topic configuration

**`bin/dot`** (daily update adapter):

- Pulls latest dotfiles from git
- Ensures and updates Homebrew
- Runs `brew bundle` to install Brewfile packages
- Executes sorted top-level `install.sh` scripts in non-reserved topic directories
- Does not reapply macOS defaults or hostname normalization

### Custom Executables

The `bin/` directory is added to PATH and contains custom git utilities and system tools. All are executable scripts that can be called directly:

**Git utilities**: `git-amend`, `git-credit`, `git-delete-local-merged`, `git-nuke`, `git-promote`, `git-rank-contributors`, `git-undo`

**System utilities**: `battery-status`, `dns-flush`, `e` (open in $EDITOR), `ee` (open current dir in $EDITOR)

### Functions

The `functions/` directory contains auto-loaded ZSH functions:

- **`c`**: Jump to project in `$PROJECTS` directory with autocomplete (uses `functions/_c` for completion)
- **`extract`**: Extract any archive format (tar, zip, rar, etc.)
- **`gf`**: Git branch switcher with fuzzy finding

Files starting with `_` in `functions/` are completion helpers (e.g., `_c` provides autocomplete for `c` command).

### Secret Management

**`~/.localrc`**: Gitignored file for sensitive environment variables (API keys, tokens, credentials). Automatically sourced by `.zshrc` on shell startup.

**`$DOTFILES_ROOT/.localrc.example`**: Template showing expected format. Bootstrap script creates `~/.localrc` from this template.

**Security**: Always `chmod 600 ~/.localrc` to restrict permissions.

### Symlink Pattern

Files ending in `.symlink` are automatically discovered by bootstrap script and linked to home directory:

- `git/gitconfig.symlink` → `~/.gitconfig`
- `zsh/zshrc.symlink` → `~/.zshrc`
- `mise/mise.toml.symlink` → `~/.mise.toml`
- `dotfiles-root.symlink` → `~/.dotfiles-root`

The bootstrap script finds all `.symlink` files (excluding `.git` and `_*` folders) and creates symlinks in `~/.{basename}`.

`~/.dotfiles-root [anchor]` is the single checkout-root interface. It follows
symlinks and prints the physical checkout containing the invoking script, so
commands and shell startup remain local to their Git worktree. Running
`dotfiles-root.symlink --install` repairs the home-directory seam without
overwriting a regular file or directory.

### Version Management

**Mise** (`~/.mise.toml`) manages language runtimes automatically:

- Node.js LTS + global packages (eas-cli, vercel, nx)
- Python 3.11 + tools (ruff, uv)
- Go 1.21
- Rust 1.83.0
- Elixir 1.18 + Erlang 27
- Terraform latest

Run `mise install` to install/update all runtimes.

## Important Notes

### When Adding New Topics

1. Create directory: `mkdir "$DOTFILES_ROOT/newtopic"`
2. Add files following naming conventions (`aliases.zsh`, `install.sh`, etc.)
3. Make install script executable: `chmod +x "$DOTFILES_ROOT/newtopic/install.sh"`
4. Run installer directly or use `dot` to execute every topic installer
5. Reload shell: `reload!`

### When Modifying Configurations

- Changes to `.zsh` files require `reload!` to take effect
- Changes to `.symlink` files affect the symlinked version in `~`
- Symlink changes require re-running `_scripts/bootstrap`
- New Homebrew packages should be added to `Brewfile`

### Git Configuration Split

Git config is split between:

- **Public**: `git/gitconfig.symlink` (tracked in git)
- **Private**: `git/gitconfig.local.symlink` (generated by bootstrap, gitignored)

The public config includes `~/.gitconfig.local` so private settings override public ones.

### macOS Specific

- `_macos/set-defaults.sh` sets macOS system defaults
- `_macos/set-hostname.sh` normalizes macOS hostname suffixes
- `dockutil/install.sh` configures dock items
- Many scripts assume macOS-specific commands (e.g., `gls` from GNU coreutils)

## Key Environment Variables

- `$DOTFILES_ROOT`: Physical path of the checkout containing the active dotfiles entrypoint
- `$PROJECTS`: Points to `~/Code` (used by `c` function)
- `$EDITOR`: Set by system/env.zsh
- `$PNPM_HOME`: pnpm global bin directory
