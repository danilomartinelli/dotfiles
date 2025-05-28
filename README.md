IT IS A WORK IN PROGRESS REPOSITORY

# [WIP] danilomartinelli dotfiles

My MacOS Environment Setup as Software Engineer at Witek - Focused on JavaScript/TypeScript development, DevOps, and infrastructure management.

## Install

Run this:

```bash
git clone https://github.com/danilomartinelli/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
script/bootstrap
```

This will symlink the appropriate files in `.dotfiles` to your home directory. Everything is configured and tweaked within `~/.dotfiles`.

## Configuration Structure

### Main Configuration (`zsh/zshrc.symlink`)

The heart of the setup is `zsh/zshrc.symlink`, which automatically loads all `.zsh` files from the dotfiles directory. Here's how it works:

**Environment Variables:**
- `$ZSH` - Points to your dotfiles directory (`~/.dotfiles`)
- `$PROJECTS` - Your main projects folder (`~/Code`) for quick navigation

**Loading Order:**
1. **Path files** (`*/path.zsh`) - Load first to set up PATH
2. **Main files** (`*.zsh`) - Core functionality and aliases  
3. **Completion files** (`*/completion.zsh`) - Load last for autocomplete

### Secret Environment Variables (`.localrc`)

Store sensitive environment variables in `~/.localrc` (not tracked in git):

```bash
# ~/.localrc
export AWS_ACCESS_KEY_ID="your-aws-key"
export GITHUB_TOKEN="your-github-token"
export DATABASE_URL="your-db-connection"
```

### Project Organization

Create your main projects directory:
```bash
mkdir -p ~/Code
```

Now you can quickly jump to projects with tab completion: `c [tab]`

### Topical Organization

Each topic gets its own directory with specific files:

```
topic/
├── *.zsh          # Any files ending in .zsh get loaded into your environment
├── path.zsh       # Any file named path.zsh is loaded first and expected to setup $PATH
├── completion.zsh # Any file named completion.zsh is loaded last for autocomplete
└── install.sh     # Any file named install.sh is executed when you run script/install
```

**Example topics in this dotfiles:**
- `zsh/` - Shell configuration and aliases
- `git/` - Git aliases and configuration  
- `macos/` - macOS system defaults
- `homebrew/` - Package management
- `vscode/` - Editor settings and extensions

### Better History Navigation

The main config includes enhanced history search:
- **Up/Down arrows** - Search through history based on current input
- **Shared history** - Commands shared across all terminal sessions
- **Timestamps** - Track when commands were executed
- **Deduplication** - No duplicate commands in history

### Maintenance

`dot` is a simple script that installs some dependencies, sets sane macOS defaults, and so on. Tweak this script, and occasionally run `dot` from time to time to keep your environment fresh and up-to-date. You can find this script in `bin/`.

## Features

- **Complete development environment** with modern tools and workflows
- **zsh with plugins** for enhanced productivity ([See Components/zsh section](#zsh))
  - matches case insensitive for lowercase
  - fix pasting with tabs doesn't perform completion
  - don't nice background tasks
  - allow functions to have local options
  - allow functions to have local traps
  - share history between sessions
  - add timestamps to history
  - adds history incrementally and share it across sessions
  - don't record dupes in history
  - don't expand aliases _before_ completion has finished
- **VS Code optimized** for JavaScript/TypeScript and DevOps workflows
- **Homebrew bundle** for automated software installation
- **Security-focused** with VPN, password management, and 2FA

## Software Stack

### Development Tools
- **VS Code** - Primary code editor with 26+ extensions
- **Android Studio** - Mobile development
- **Figma** - Design and prototyping
- **GitKraken** - Git GUI client
- **TablePlus** - Database management

### DevOps & Infrastructure
- **Docker** (OrbStack) - Container management
- **Kubernetes** (Lens, Helm, Helmfile) - Container orchestration
- **AWS CLI** - Cloud infrastructure
- **Cloudflare Tunnel** - Secure connections
- **ngrok** - Local tunnel exposure

### Command Line Tools
- **mise** - Runtime version manager (replaces asdf)
- **git + git-lfs** - Version control
- **jq** - JSON processor
- **imagemagick** - Image manipulation
- **wget** - File downloads

### Productivity Apps
- **Raycast** - Enhanced Spotlight with extensions
- **Rectangle Pro** - Window management
- **CleanShot** - Screenshots and screen recording
- **Fantastical** - Calendar management
- **Todoist** - Task management
- **Obsidian** - Knowledge management

### Communication & Organization
- **Readdle Spark** - Email client
- **WhatsApp** - Messaging
- **Cardhop** - Contact management
- **Bartender** - Menu bar organization

### Security & Privacy
- **Bitwarden** - Password manager
- **ProtonVPN** - VPN client
- **Yubico Authenticator** - 2FA with YubiKey
- **Zen Browser** - Privacy-focused browsing

## VS Code Extensions

Optimized setup with 26 extensions for JavaScript/TypeScript development:

### Essential Development
- **ESLint** + **Prettier** - Code quality and formatting
- **TypeScript Next** - Latest TypeScript features  
- **Console Ninja** - Advanced debugging
- **Error Lens** - Inline error highlighting

### Git Integration
- **GitLens** - Git supercharged
- **Git Blame** - Inline annotations

### Productivity Enhancers
- **Path IntelliSense** - File path autocomplete
- **NPM IntelliSense** - Package autocomplete
- **Import Cost** - Bundle size visualization
- **Auto Close/Rename Tag** - HTML/XML helpers

### Framework Support
- **Tailwind CSS** - Utility-first CSS framework
- **React Native Tools** - Mobile development
- **PostCSS** - CSS preprocessing

### DevOps & Infrastructure
- **Docker** - Container support
- **Remote Development** - SSH, containers, WSL
- **YAML** + **TOML** - Configuration files
- **SQLTools** - Database management (MySQL, PostgreSQL, SQLite)

## CheatSheet

### Navigation
| Command   | Description                                    |
| --------- | ---------------------------------------------- |
| `c [tab]` | Quick navigation to projects in `~/Code`      |
| `..`      | Go up one directory                            |
| `...`     | Go up two directories                          |

### Shell Management  
| Alias     | Command      | Description                                    |
| --------- | ------------ | ---------------------------------------------- |
| `reload!` | `. ~/.zshrc` | Reload all zsh settings in the current session |
| `cls`     | `clear`      | Clear the session buffer                       |

### Git Shortcuts
| Alias     | Command              | Description                     |
| --------- | -------------------- | ------------------------------- |
| `gs`      | `git status`         | Check repository status         |
| `ga`      | `git add`            | Stage files                     |
| `gc`      | `git commit`         | Commit changes                  |
| `gp`      | `git push`           | Push to remote                  |
| `gl`      | `git pull`           | Pull from remote                |

### Project Management
```bash
# Quick project setup
cd ~/Code
mkdir my-new-project
cd my-new-project
git init

# Navigate from anywhere
c my-new-project  # Tab completion works!
```

### Environment Variables
```bash
# Check current environment
echo $ZSH          # ~/.dotfiles
echo $PROJECTS     # ~/Code  

# Add secrets to ~/.localrc (not tracked)
echo 'export API_KEY="secret"' >> ~/.localrc
source ~/.localrc
```

## Components

### zsh

Enhanced shell experience with automatic loading system:

- **[zsh-better-history](https://coderwall.com/p/jpj_6q/zsh-better-history-searching-with-arrow-keys)** - Smart history navigation
- **Case insensitive matching** for lowercase input
- **Tab completion fixes** - No unwanted expansions during paste
- **Session history sharing** - Commands available across all terminals
- **Timestamped history** - Track when commands were executed
- **Incremental updates** - History saved immediately, not on exit
- **Duplicate prevention** - Clean, organized command history

### git

Git workflow optimization:
- **Custom aliases** for common operations
- **Enhanced git status** and log formatting
- **Branch management** helpers
- **Integration with GitLens** and GitKraken

### homebrew  

Package management automation:
- **Brewfile** with 60+ packages and applications
- **Automatic installation** via `script/bootstrap`
- **Extension management** for VS Code
- **Mac App Store** integration

### vscode

Editor configuration for JavaScript/TypeScript development:
- **26 curated extensions** for modern web development
- **Optimized settings** for productivity
- **DevOps tooling** integration
- **Theme and font** consistency

### macos

System preferences and defaults:
- **Productivity settings** - Dock, Finder, keyboard
- **Developer optimizations** - File visibility, permissions
- **Security configurations** - Privacy and access controls
- **Performance tuning** - Animation speeds, energy settings

### Example Topic Structure

Want to add your own topic? Here's the pattern:

```bash
# Create topic directory
mkdir -p ~/.dotfiles/nodejs

# Add path configuration
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' > ~/.dotfiles/nodejs/path.zsh

# Add aliases and functions  
cat > ~/.dotfiles/nodejs/nodejs.zsh << 'EOF'
alias ni="npm install"
alias nid="npm install --save-dev" 
alias nig="npm install --global"
alias nrs="npm run start"
alias nrd="npm run dev"
EOF

# Add completions
echo 'eval "$(npm completion bash)"' > ~/.dotfiles/nodejs/completion.zsh

# Add installation script
cat > ~/.dotfiles/nodejs/install.sh << 'EOF'
#!/bin/bash
# Install global npm packages
npm install -g typescript@latest
npm install -g @vercel/cli
EOF
```

After creating files, restart your shell or run `source ~/.zshrc` to load changes.

### Brewfile Structure

```ruby
# Command line tools (11 packages)
brew 'awscli', 'cloudflared', 'git', 'git-lfs', 'helm', 'helmfile', 
     'imagemagick', 'jq', 'mas', 'mise', 'wget'

# Desktop applications (23 apps)
cask 'android-studio', 'apidog', 'bartender', 'bitwarden', 'cardhop',
     'cleanshot', 'fantastical', 'figma', 'font-fira-code', 'font-fira-mono',
     'ghostty', 'gitkraken', 'lens', 'ngrok', 'obsidian', 'orbstack',
     'protonvpn', 'raycast', 'readdle-spark', 'rectangle-pro', 'spotify',
     'tableplus', 'todoist', 'visual-studio-code', 'vlc', 'whatsapp', 'zen'

# Mac App Store (2 apps)
mas 'Yubico Authenticator', 'Xcode'

# VS Code Extensions (26 extensions)
# See full list in Brewfile
```

## Project Structure

```
~/.dotfiles/
├── Brewfile                    # Package management
├── script/
│   ├── bootstrap              # Initial setup script
│   └── install                # Install all topic dependencies
├── bin/
│   └── dot                    # Update/maintenance script
├── zsh/
│   ├── zshrc.symlink         # Main shell configuration
│   ├── aliases.zsh           # Shell aliases
│   └── completion.zsh        # Tab completions
├── git/
│   ├── gitconfig.symlink     # Git configuration
│   └── gitignore.symlink     # Global git ignore
├── vscode/
│   ├── settings.json         # VS Code settings
│   ├── keybindings.json      # Custom shortcuts
│   └── snippets/             # Code snippets
├── macos/
│   ├── set-defaults.sh       # System preferences
│   └── dock.sh               # Dock configuration  
└── topic/
    ├── *.zsh                 # Loaded into environment
    ├── path.zsh              # Loaded first (PATH setup)
    ├── completion.zsh        # Loaded last (completions)
    └── install.sh            # Executed on script/install
```

### Key Directories

- **`~/Code/`** - Your main projects directory (customizable via `$PROJECTS`)
- **`~/.localrc`** - Private environment variables (not tracked by git)
- **`~/.dotfiles/`** - This repository (accessible via `$ZSH`)

### File Naming Conventions

- **`.symlink`** - Files that get symlinked to `$HOME`
- **`*.zsh`** - Shell scripts loaded automatically  
- **`path.zsh`** - PATH modifications (loaded first)
- **`completion.zsh`** - Tab completions (loaded last)
- **`install.sh`** - Installation scripts for topics

## Installation Notes

- **Fonts**: Fira Code and Fira Mono included for optimal coding experience
- **Runtime Management**: Using `mise` instead of `asdf` for better performance
- **Container Platform**: OrbStack preferred over Docker Desktop for macOS
- **Terminal**: Ghostty as modern terminal emulator

---

**Stack Focus**: JavaScript/TypeScript • DevOps • Cloud Infrastructure • Security
