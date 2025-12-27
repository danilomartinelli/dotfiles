# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

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
# Update everything (dotfiles, brew packages, run all installers)
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

# Re-run all installers
_scripts/install

# Re-run bootstrap (re-symlink configs)
_scripts/bootstrap
```

### Testing & Validation
```bash
# Reload shell configuration (after making changes)
source ~/.zshrc
# or use alias:
reload!

# Test shell functions
c <tab>              # Test project directory autocomplete
extract file.zip     # Test archive extraction
```

## Architecture & Code Structure

### Topic-Based Organization

The repository uses a **topic directory pattern** where each tool/topic (git, docker, zsh, etc.) has its own directory with standardized filenames:

```
topic/
├── install.sh       # Runs during _scripts/install (optional)
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

The `.zshrc` loads configuration in this precise order (defined in `zsh/zshrc.symlink`):

1. **Environment setup**: Sets `$ZSH` (`~/.dotfiles`) and `$PROJECTS` (`~/Code`)
2. **Local secrets**: Sources `~/.localrc` (gitignored sensitive vars)
3. **Common vars**: Sources `.commonrc` (non-sensitive shared vars)
4. **PATH files**: All `*/path.zsh` files from non-ignored topics
5. **Main configs**: All `*.zsh` files (except path.zsh and completion.zsh)
6. **Completions init**: Runs `compinit`
7. **Completion files**: All `*/completion.zsh` files

### Key Scripts

**`_scripts/bootstrap`** (first-time setup):
- Prompts for git author name/email
- Creates `git/gitconfig.local.symlink` from template
- Symlinks all `*.symlink` files to home directory
- Creates `~/.localrc` from `.localrc.example`
- Runs `_macos/install.sh` for macOS defaults
- Calls `bin/dot` to install dependencies

**`bin/dot`** (update script):
- Pulls latest dotfiles from git
- Installs/upgrades Homebrew
- Runs `brew bundle` to install Brewfile packages
- Executes all `install.sh` scripts in topic directories

**`_scripts/install`**:
- Sets up Homebrew taps
- Runs `brew bundle` against Brewfile
- Finds and executes all `install.sh` files (excluding `_*` folders)

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

**`~/.dotfiles/.localrc.example`**: Template showing expected format. Bootstrap script creates `~/.localrc` from this template.

**Security**: Always `chmod 600 ~/.localrc` to restrict permissions.

### Symlink Pattern

Files ending in `.symlink` are automatically discovered by bootstrap script and linked to home directory:
- `git/gitconfig.symlink` → `~/.gitconfig`
- `zsh/zshrc.symlink` → `~/.zshrc`
- `mise/mise.toml.symlink` → `~/.mise.toml`

The bootstrap script finds all `.symlink` files (excluding `.git` and `_*` folders) and creates symlinks in `~/.{basename}`.

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

1. Create directory: `mkdir ~/.dotfiles/newtopic`
2. Add files following naming conventions (`aliases.zsh`, `install.sh`, etc.)
3. Make install script executable: `chmod +x ~/.dotfiles/newtopic/install.sh`
4. Run installer: `~/.dotfiles/newtopic/install.sh` or `_scripts/install`
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

- `_macos/install.sh` sets macOS system defaults
- `dockutil/install.sh` configures dock items
- Many scripts assume macOS-specific commands (e.g., `gls` from GNU coreutils)

## Key Environment Variables

- `$ZSH`: Points to `~/.dotfiles`
- `$PROJECTS`: Points to `~/Code` (used by `c` function)
- `$EDITOR`: Set by system/env.zsh
- `$PNPM_HOME`: pnpm global bin directory
