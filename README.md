# danilomartinelli's dotfiles

> Personal macOS development environment configuration for JavaScript/TypeScript, DevOps, and infrastructure management.

## 🚀 Quick Start

### Prerequisites

- macOS (tested on Darwin 24.5.0)
- Git
- Command Line Tools for Xcode (`xcode-select --install`)

### Installation

```bash
# Clone the repository
git clone https://github.com/danilomartinelli/dotfiles.git ~/.dotfiles

# Navigate to dotfiles
cd ~/.dotfiles

# Run the bootstrap script (first-time setup)
script/bootstrap

# This will:
# - Set up git configuration (prompts for name/email)
# - Create symlinks for all config files
# - Install Homebrew and all dependencies
# - Configure macOS defaults
```

### Quick Update Command

```bash
# Update dotfiles, brew packages, and run all installers
bin/dot
```

## 📂 Repository Structure

```text
.dotfiles/
├── bin/                 # Custom executable scripts
├── functions/           # ZSH functions (auto-loaded)
├── script/              # Setup and management scripts
├── _docs/               # Documentation (ignored by installers)
├── */                   # Topic directories (see below)
├── Brewfile            # Homebrew packages and apps
├── CLAUDE.md           # Claude AI instructions
└── localrc.example     # Template for local secrets
```

### Topic Directory Structure

Each topic follows this standard structure:

```text
topic/
├── install.sh       # Installation script (optional)
├── *.symlink        # Files to be symlinked to ~
├── path.zsh         # PATH modifications (loaded first)
├── aliases.zsh      # Command aliases
├── env.zsh          # Environment variables
├── completion.zsh   # Shell completions (loaded last)
└── *.zsh           # Other configs (auto-loaded)
```

**⚠️ Important Architecture Rules:**
- Folders starting with `_` are completely ignored (e.g., `_docs/`, `_archive/`)
- Files starting with `_` are ignored even in regular folders
- Standard file names must be exact: `path.zsh`, `aliases.zsh`, `completion.zsh`
- Installation scripts must be named `install.sh`
- Files ending in `.symlink` are automatically linked to home directory

## 🛠 Installed Tools

### Command Line Tools (via Homebrew)

| Tool | Description |
|------|-------------|
| `awscli` | AWS Command Line Interface |
| `coreutils` | GNU File, Shell, and Text utilities |
| `dockutil` | Manage macOS dock items |
| `duti` | Set default applications for file types |
| `git` & `git-lfs` | Version control with large file support |
| `gh` | GitHub CLI |
| `helm` & `helmfile` | Kubernetes package management |
| `imagemagick` | Image manipulation |
| `jq` & `yq` | JSON/YAML processors |
| `kubernetes-cli` & `kustomize` | Kubernetes tools |
| `mas` | Mac App Store CLI |
| `mise` | Runtime version manager |
| `pandoc` | Document converter |
| `spaceman-diff` | Visual diff for images |
| `terragrunt` | Terraform wrapper |
| `vim` | Text editor |
| `watchman` | File watching service |
| `wget` | File download utility |

### Desktop Applications

| Application | Description |
|------------|-------------|
| **Development** |  |
| Android Studio | Android development IDE |
| Xcode | Apple development IDE |
| Ghostty | Modern terminal emulator |
| OrbStack | Docker Desktop alternative |
| Lens | Kubernetes IDE |
| TablePlus | Database management |
| Ngrok | Secure tunnels to localhost |
| **Productivity** |  |
| Arc | Privacy-focused browser |
| Claude | AI assistant desktop client |
| Notion | Knowledge management |
| Raycast | Spotlight replacement with extensions |
| Rectangle Pro | Window management |
| Paste | Clipboard manager |
| **Design & Media** |  |
| Figma | Design tool |
| CleanShot | Screenshot and recording |
| PDF Expert | PDF editor |
| **Communication** |  |
| Readdle Spark | Smart email client |
| **Security** |  |
| Bitwarden | Password manager |
| ProtonVPN | VPN client |
| Yubico Authenticator | 2FA with YubiKey |
| **Other** |  |
| Spotify | Music streaming |
| Kindle | eBook reader |
| Archiver | File compression |
| iMazing | iOS device management |
| Apidog | API development and testing |

### Development Runtimes (via Mise)

Mise automatically manages versions for:

- **Node.js** (LTS) with Bun, npm, pnpm, yarn
- **Python** (3.11) with ruff, uv
- **Go** (1.21)
- **Rust** (1.83.0)
- **Elixir** (1.18) with Erlang (27)
- **Terraform** (latest)

Global npm packages:

- `eas-cli` - Expo Application Services
- `vercel` - Vercel CLI
- `nx` - Monorepo tool

## ⌨️ Aliases & Functions

### Git Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `gl` | `git pull --prune` | Pull with pruning |
| `glog` | Enhanced git log | Pretty git log with graph |
| `gp` | `git push origin HEAD` | Push current branch |
| `gd` | `git diff --color` | Colored diff |
| `gc` | `git commit -v` | Commit with verbose |
| `gca` | `git commit -v -a` | Commit all with verbose |
| `gco` | `git checkout` | Checkout |
| `gcb` | `git copy-branch-name` | Copy current branch name |
| `gb` | `git branch` | List branches |
| `gs` | `git status -sb` | Short status |
| `gac` | `git add -A && git commit -v` | Add all and commit |
| `ge` | `git-edit-new` | Edit new files |

### System Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `reload!` | `. ~/.zshrc` | Reload shell configuration |
| `cls` | `clear` | Clear screen |
| `ls` | `gls -F --color` | Colorized ls with indicators |
| `l` | `gls -lAh --color` | Long format with hidden files |
| `ll` | `gls -l --color` | Long format |
| `la` | `gls -A --color` | All files |

### Docker Aliases

| Alias | Command |
|-------|---------|
| `d` | `docker` |
| `dc` | `docker-compose` |

### Platform-Specific

| Alias | Command | Description |
|-------|---------|-------------|
| `ios` | Opens iOS Simulator | Launch iOS Simulator |
| `android` | `emulator -list-avds \| head -1 \| xargs emulator -avd` | Launch Android emulator |
| `sshclean` | `rm -f ~/.ssh/sockets/*` | Clean SSH sockets |

### Custom Functions

| Function | Description | Usage |
|----------|-------------|-------|
| `c` | Jump to project directory | `c project-name` |
| `extract` | Extract any archive file | `extract file.zip` |
| `gf` | Switch git branch | `gf branch-name` |
| `use_kubeconfig` | Switch Kubernetes config | `use_kubeconfig config-name` |
| `use_aws_profile` | Switch AWS profile | `use_aws_profile profile-name` |
| `use_vercel` | Load Vercel env | `use_vercel` |
| `run_vercel` | Run with Vercel env | `run_vercel command` |

## 🔐 Secret Management

### Local Secrets (.localrc)

All sensitive environment variables should be stored in `~/.localrc` (not tracked in git). This file is automatically sourced by `.zshrc` on shell startup, making all variables available in your shell sessions.

#### Setting Up .localrc

```bash
# Create your local configuration file
touch ~/.localrc
chmod 600 ~/.localrc  # Restrict permissions for security

# Add your secrets and environment variables
cat >> ~/.localrc << 'EOF'
# API Keys and Tokens
export GITHUB_TOKEN="your-github-token"
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-..."

# AWS Credentials
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"

# Database Connections
export DATABASE_URL="postgresql://user:pass@host:5432/db"
export REDIS_URL="redis://localhost:6379"

# Application Secrets
export JWT_SECRET="your-jwt-secret"
export SESSION_SECRET="your-session-secret"

# Custom Configuration
export MY_APP_ENV="development"
export API_BASE_URL="https://api.example.com"
EOF
```

#### Best Practices

- **Security**: Always use `chmod 600 ~/.localrc` to ensure only you can read the file
- **Organization**: Group related variables with comments
- **Updates**: Variables are loaded on shell startup; run `reload!` (alias for `source ~/.zshrc`) to apply changes immediately
- **Backup**: Keep a secure backup of your secrets in a password manager (like Bitwarden)

#### Example .localrc Template

A template file is provided at `localrc.example` to help you get started:

```bash
# Copy the template and customize it
cp ~/.dotfiles/localrc.example ~/.localrc
chmod 600 ~/.localrc
# Edit with your actual values
vim ~/.localrc
```

## 🗂 Creating New Topics

To add a new tool or configuration:

1. **Create a topic directory**:

```bash
mkdir ~/.dotfiles/your-tool
```

2. **Add configuration files**:

```bash
# Symlinked configuration
echo "config" > ~/.dotfiles/your-tool/config.symlink

# Shell configuration
echo "alias yt='your-tool'" > ~/.dotfiles/your-tool/aliases.zsh

# PATH modifications
echo 'export PATH="/path/to/your-tool:$PATH"' > ~/.dotfiles/your-tool/path.zsh

# Installation script
cat > ~/.dotfiles/your-tool/install.sh << 'EOF'
#!/bin/sh
echo "› Installing your-tool"
# Installation commands here
EOF
chmod +x ~/.dotfiles/your-tool/install.sh
```

3. **Run the installer**:

```bash
~/.dotfiles/your-tool/install.sh
# Or run all installers
script/install
```

## 📚 Documentation

Comprehensive documentation is available in the `_docs/` folder:

- **[📖 Documentation Overview](_docs/README.md)** - Complete guide with features, installation, and customization
- **[🏗 Architecture](_docs/ARCHITECTURE.md)** - System design, component interactions, and data flow
- **[📦 Installation Scripts](_docs/INSTALL_SCRIPTS.md)** - Detailed guide to all installation scripts
- **[⚙️ Configuration Reference](_docs/CONFIGURATION.md)** - Complete configuration file reference

## 🔧 Configuration Details

### ZSH Loading Order

The `.zshrc` loads configuration files in this specific order:

1. **Environment**: Sets `$ZSH` and `$PROJECTS` variables
2. **Local secrets**: Sources `~/.localrc` if it exists
3. **Path files**: All `*/path.zsh` files (PATH setup)
4. **Main configs**: All `*.zsh` files except path and completion
5. **Completions**: All `*/completion.zsh` files (after compinit)

### Symlink Management

Files with `.symlink` extension are automatically linked to your home directory:

- `git/gitconfig.symlink` → `~/.gitconfig`
- `zsh/zshrc.symlink` → `~/.zshrc`
- `mise/mise.toml.symlink` → `~/.mise.toml`

### Git Configuration

Git uses a split configuration:

- Public settings: `git/gitconfig.symlink`
- Private settings: `git/gitconfig.local.symlink` (generated on bootstrap)
  - Contains your name, email, and credential helper

### SSH Configuration

SSH setup includes:

- OrbStack container access
- Multiple GitHub account support
- Development/staging/production server configs
- Connection keepalive settings
- Socket cleanup alias

### macOS Defaults

The `macos/set-defaults.sh` script configures:

- System preferences
- Finder settings
- Dock configuration
- Security preferences

## 📦 Custom Scripts

The `bin/` directory contains custom utilities:

### Git Utilities

- `git-amend` - Amend the last commit
- `git-credit` - Credit an author on commits
- `git-delete-local-merged` - Delete merged branches
- `git-nuke` - Remove a branch locally and remotely
- `git-promote` - Promote a branch to main
- `git-rank-contributors` - Rank git contributors
- `git-undo` - Undo the last commit

### System Utilities

- `battery-status` - Check battery status
- `dns-flush` - Flush DNS cache
- `dot` - Update dotfiles and dependencies
- `e` - Open in $EDITOR
- `ee` - Open current directory in $EDITOR

## 🔄 Maintenance

### Update Everything

```bash
# Pull latest dotfiles, update brew, and run installers
bin/dot
```

### Update Specific Components

```bash
# Update Homebrew packages
brew update && brew upgrade

# Update dotfiles only
git -C ~/.dotfiles pull

# Reinstall dotfiles
~/.dotfiles/script/bootstrap

# Run all installers
~/.dotfiles/script/install
```

### Add New Homebrew Packages

```bash
# Install a new package
brew install package-name

# Add it to Brewfile for persistence
echo "brew 'package-name'" >> ~/.dotfiles/Brewfile
```

## 🤝 Contributing

Feel free to fork this repository and customize it for your own use. If you have improvements that might benefit others, please submit a pull request!

## 📝 Notes

- This setup is specifically tailored for macOS development
- The configuration assumes you're using ZSH as your shell
- Many tools and configurations are specific to JavaScript/TypeScript and DevOps workflows
- Always review scripts before running them on your system

## 📄 License

This repository contains personal configuration files. Feel free to use any part of this setup in your own dotfiles!

## 🙏 Acknowledgments

Inspired by and borrowed from many amazing dotfiles repositories in the community.
