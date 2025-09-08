# 🏠 Dotfiles - macOS Development Environment

[![macOS](https://img.shields.io/badge/macOS-000000?style=flat-square&logo=apple&logoColor=F0F0F0)](https://support.apple.com/macos)
[![Zsh](https://img.shields.io/badge/Zsh-4EAA25?style=flat-square&logo=zsh&logoColor=white)](https://www.zsh.org/)
[![Homebrew](https://img.shields.io/badge/Homebrew-FBB040?style=flat-square&logo=homebrew&logoColor=black)](https://brew.sh/)
[![VS Code](https://img.shields.io/badge/VS_Code-007ACC?style=flat-square&logo=visual-studio-code&logoColor=white)](https://code.visualstudio.com/)

A comprehensive, modular dotfiles system for macOS development environment configuration. Manages system settings, shell configuration, development tools, and application preferences through automated installation and symlink management.

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/danilomartinelli/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# Bootstrap the system (first-time setup)
script/bootstrap

# Or update existing installation
bin/dot
```

## 📋 Table of Contents

- [Features](#-features)
- [System Requirements](#-system-requirements)
- [Installation](#-installation)
- [Architecture](#-architecture)
- [Configuration Topics](#-configuration-topics)
- [Commands](#-commands)
- [Customization](#-customization)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

## ✨ Features

### 🔧 System Configuration
- **macOS Defaults**: Optimized system preferences for developers
- **Shell Environment**: Advanced Zsh configuration with completions
- **Path Management**: Automatic PATH configuration for all tools
- **Git Configuration**: Split public/private git settings
- **SSH Setup**: Automated SSH key generation and configuration

### 🛠 Development Tools
- **Package Management**: Homebrew with declarative Brewfile
- **Runtime Management**: Mise for Node.js, Python, Go, Rust, and more
- **Editor Configuration**: VS Code with 60+ curated extensions
- **Terminal Setup**: Ghostty terminal with optimal settings
- **Container Tools**: Docker, Kubernetes, and OrbStack integration

### 🎯 Productivity Features
- **Claude Integration**: AI assistant configuration and agents
- **Git Utilities**: 15+ custom git commands and aliases
- **System Utilities**: Battery status, DNS flush, search tools
- **Dock Management**: Automated application dock configuration
- **Security**: Bitwarden integration for secret management

### 🔄 Automation
- **Self-Updating**: Automated updates for dotfiles and packages
- **Modular Design**: Topic-based organization for easy maintenance
- **Symlink Management**: Automatic configuration file linking
- **Installation Scripts**: Per-topic setup automation

## 🖥 System Requirements

- **Operating System**: macOS 10.15+ (Catalina or later)
- **Shell**: Zsh (default on macOS 10.15+)
- **Xcode Command Line Tools**: Automatically installed
- **Internet Connection**: Required for downloading packages

## 🚀 Installation

### First-Time Setup

```bash
# 1. Clone the repository
git clone https://github.com/danilomartinelli/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# 2. Run bootstrap script
script/bootstrap
```

The bootstrap script will:
1. Set up git configuration (prompts for name/email)
2. Create symlinks for configuration files
3. Install Homebrew and all dependencies
4. Configure macOS defaults
5. Set up all development tools

### Updating Existing Installation

```bash
# Update everything
bin/dot

# Update specific components
script/install          # Run all install scripts
brew bundle             # Update Homebrew packages
mise install           # Update runtime versions
```

## 🏗 Architecture

### Core Loading System

The system uses a **topic-based architecture** where each directory represents a configuration area:

```
~/.dotfiles/
├── topic1/
│   ├── *.zsh           # Auto-loaded shell configuration
│   ├── path.zsh        # PATH modifications (loaded first)
│   ├── completion.zsh  # Shell completions (loaded last)
│   ├── aliases.zsh     # Command aliases
│   ├── *.symlink       # Files to symlink to home directory
│   └── install.sh      # Installation script
└── topic2/
    └── ...
```

### Loading Order

1. **Path Setup** (`*/path.zsh`) - Environment PATH configuration
2. **Main Config** (`*.zsh`) - Core functionality and settings
3. **Completions** (`*/completion.zsh`) - Shell auto-completions

### Symlink Management

Files ending in `.symlink` are automatically linked to your home directory:

```bash
# Example:
git/gitconfig.symlink → ~/.gitconfig
vim/vimrc.symlink     → ~/.vimrc
zsh/zshrc.symlink     → ~/.zshrc
```

## 📁 Configuration Topics

| Topic | Description | Key Files |
|-------|-------------|-----------|
| **git** | Git configuration and aliases | `gitconfig.symlink`, `aliases.zsh` |
| **zsh** | Shell configuration and prompt | `zshrc.symlink`, `config.zsh`, `prompt.zsh` |
| **code** | VS Code settings and extensions | `settings.json`, `keybindings.json`, `install.sh` |
| **homebrew** | Package management | `Brewfile`, `install.sh` |
| **mise** | Runtime version management | `mise.toml.symlink`, `mise.zsh` |
| **ssh** | SSH configuration and keys | `config`, `install.sh` |
| **macos** | System defaults and hostname | `set-defaults.sh`, `set-hostname.sh` |
| **claude** | AI assistant configuration | `agents/`, `commands/`, `install.sh` |
| **ghostty** | Terminal configuration | `config` |
| **docker** | Container development | `aliases.zsh` |

## 🎮 Commands

### Core Commands

```bash
# System management
bin/dot                    # Update everything
script/bootstrap          # First-time setup
script/install           # Run all install scripts

# Git utilities
bin/git-up               # Smart git pull with log
bin/git-wtf              # Git repository status overview
bin/git-nuke <branch>    # Delete branch locally and remotely
bin/git-promote          # Promote local branch to remote
bin/git-credit <name> <email>  # Credit co-author

# System utilities
bin/battery-status       # Show battery information
bin/dns-flush           # Flush DNS cache
bin/search <term>       # Search in current directory
bin/e [file]            # Open in default editor
```

### Claude Integration

```bash
# AI-powered development
claude                   # Start Claude Code assistant
yolo                     # Claude without permission prompts

# Available agents (in ~/.claude/agents/):
# - backend-architect     - python-pro
# - frontend-developer    - typescript-pro  
# - devops-troubleshooter - security-auditor
# - database-optimizer    - performance-engineer
# + 40 more specialized agents
```

## 🎨 Customization

### Adding New Topics

1. Create a new directory: `mkdir ~/.dotfiles/newtopic`
2. Add configuration files:
   ```bash
   # Shell configuration
   echo "# New topic config" > newtopic/config.zsh
   
   # Installation script
   cat > newtopic/install.sh << 'EOF'
   #!/bin/sh
   echo "Installing newtopic..."
   # Add installation commands
   EOF
   chmod +x newtopic/install.sh
   ```

### Private Configuration

Add private settings to files that are gitignored:

```bash
# Private git settings
~/.gitconfig.local

# Private shell settings  
~/.localrc

# Private SSH config
~/.dotfiles/ssh/config_local
```

### Extending VS Code

Add extensions to the list in `code/install.sh`:

```bash
extensions=(
  "existing.extension"
  "your.new.extension"
)
```

### Custom Aliases

Add to any topic's `aliases.zsh`:

```bash
# In ~/.dotfiles/yourtopic/aliases.zsh
alias mycommand='echo "Hello World"'
```

## 🔧 Troubleshooting

### Common Issues

**Command not found after installation**
```bash
# Reload shell configuration
source ~/.zshrc

# Or restart terminal
```

**Symlink conflicts**
```bash
# Bootstrap will prompt for each conflict:
# [s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all
```

**Homebrew installation fails**
```bash
# Check Xcode Command Line Tools
xcode-select --install

# Reset Homebrew
rm -rf /opt/homebrew
script/bootstrap
```

**VS Code extensions not installing**
```bash
# Check if 'code' command is in PATH
which code

# Install manually if needed:
# Open VS Code > Cmd+Shift+P > "Install 'code' command in PATH"
```

### Debug Information

```bash
# Check system info
echo "OS: $(sw_vers -productName) $(sw_vers -productVersion)"
echo "Shell: $SHELL"
echo "Homebrew: $(brew --version | head -1)"
echo "Git: $(git --version)"

# Check dotfiles status
ls -la ~/.dotfiles/*/install.sh
ls -la ~/.*symlink* 2>/dev/null || echo "No broken symlinks"
```

## 📚 Documentation

- [Architecture Overview](./docs/ARCHITECTURE.md)
- [Installation Scripts Reference](./docs/INSTALL_SCRIPTS.md)
- [Configuration Reference](./docs/CONFIGURATION.md)
- [Git Utilities Guide](./docs/GIT_UTILITIES.md)
- [Claude Integration Guide](./docs/CLAUDE.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Test your changes thoroughly
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

### Development Guidelines

- **Topic Organization**: Group related configurations together
- **Installation Scripts**: Make them idempotent and safe to re-run
- **Cross-Platform**: Consider compatibility even though focused on macOS
- **Documentation**: Update docs for any user-facing changes

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 🙏 Acknowledgments

- [Holman's dotfiles](https://github.com/holman/dotfiles) - Original architecture inspiration
- [mathiasbynens/dotfiles](https://github.com/mathiasbynens/dotfiles) - macOS defaults
- [Homebrew](https://brew.sh/) - Package management
- [Mise](https://mise.jdx.dev/) - Runtime management
- [Claude](https://claude.ai/) - AI development assistant

---

*Built with ❤️ for productive macOS development*