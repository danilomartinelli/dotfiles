# 🏗 Architecture Overview

This document provides a comprehensive overview of the dotfiles architecture, including system design, component interactions, and data flow patterns.

## Table of Contents

- [System Architecture](#system-architecture)
- [Component Diagram](#component-diagram)
- [Loading Sequence](#loading-sequence)
- [File Organization](#file-organization)
- [Extension Points](#extension-points)
- [Security Model](#security-model)
- [Performance Considerations](#performance-considerations)

## System Architecture

```mermaid
graph TB
    subgraph "User Environment"
        Terminal[Terminal Session]
        Shell[Zsh Shell]
        Editor[VS Code]
        Git[Git Operations]
    end

    subgraph "Dotfiles Core"
        Bootstrap[script/bootstrap]
        Installer[script/install] 
        Updater[bin/dot]
        ZshRC[zsh/zshrc.symlink]
    end

    subgraph "Configuration Topics"
        GitTopic[git/]
        ZshTopic[zsh/]
        CodeTopic[code/]
        HomebrewTopic[homebrew/]
        MiseTopic[mise/]
        SSHTopic[ssh/]
        MacOSTopic[macos/]
        ClaudeTopic[claude/]
    end

    subgraph "Package Managers"
        Homebrew[Homebrew<br/>System Packages]
        Mise[Mise<br/>Runtime Versions]
        NPM[npm<br/>Node Packages]
        VSCodeExt[VS Code<br/>Extensions]
    end

    subgraph "External Services"
        GitHub[GitHub]
        Claude[Claude AI]
        Bitwarden[Bitwarden]
    end

    Terminal --> Shell
    Shell --> ZshRC
    ZshRC --> GitTopic
    ZshRC --> ZshTopic
    ZshRC --> MiseTopic

    Bootstrap --> Installer
    Updater --> Installer
    Installer --> GitTopic
    Installer --> CodeTopic
    Installer --> HomebrewTopic
    Installer --> MacOSTopic

    HomebrewTopic --> Homebrew
    CodeTopic --> VSCodeExt
    MiseTopic --> Mise
    ClaudeTopic --> Claude

    GitTopic --> GitHub
    SSHTopic --> GitHub
```

## Component Diagram

### Core Components

```mermaid
classDiagram
    class DotfilesSystem {
        +bootstrap()
        +install()
        +update()
        +symlink_files()
    }

    class Topic {
        +name: string
        +path: string
        +has_install_script(): bool
        +has_symlinks(): bool
        +install()
        +load_config()
    }

    class SymlinkManager {
        +create_symlink(source, target)
        +backup_existing(file)
        +prompt_user_action()
        +verify_symlinks()
    }

    class ConfigLoader {
        +load_path_configs()
        +load_main_configs() 
        +load_completions()
        +source_file(file)
    }

    class InstallRunner {
        +run_all_installers()
        +run_topic_installer(topic)
        +check_dependencies()
        +handle_errors()
    }

    DotfilesSystem --> Topic
    DotfilesSystem --> SymlinkManager
    DotfilesSystem --> ConfigLoader
    DotfilesSystem --> InstallRunner
    
    Topic --> SymlinkManager
    Topic --> ConfigLoader
```

### Topic Structure

```mermaid
graph LR
    subgraph "Topic Directory"
        InstallScript[install.sh]
        PathConfig[path.zsh]
        MainConfig[*.zsh]
        Completions[completion.zsh]
        Aliases[aliases.zsh]
        Symlinks[*.symlink]
    end

    subgraph "Loading Order"
        Path[1. Path Setup]
        Main[2. Main Config]
        Comp[3. Completions]
    end

    subgraph "Installation"
        Install[install.sh execution]
        Link[Symlink creation]
    end

    PathConfig --> Path
    MainConfig --> Main
    Aliases --> Main
    Completions --> Comp
    
    InstallScript --> Install
    Symlinks --> Link
```

## Loading Sequence

### Shell Initialization Flow

```mermaid
sequenceDiagram
    participant User
    participant Zsh
    participant ZshRC as zshrc.symlink
    participant Topics
    participant External

    User->>Zsh: Start shell session
    Zsh->>ZshRC: Source ~/.zshrc
    
    Note over ZshRC: Set environment variables
    ZshRC->>ZshRC: Export ZSH, PROJECTS paths
    
    Note over ZshRC: Load PATH configurations
    loop For each */path.zsh
        ZshRC->>Topics: Source path.zsh
        Topics-->>ZshRC: PATH updates
    end
    
    Note over ZshRC: Load main configurations
    loop For each *.zsh (excluding path/completion)
        ZshRC->>Topics: Source config file
        Topics-->>ZshRC: Functions, aliases, settings
    end
    
    Note over ZshRC: Load completions last
    loop For each */completion.zsh
        ZshRC->>Topics: Source completion.zsh
        Topics-->>ZshRC: Completion functions
    end
    
    Note over ZshRC: Initialize external tools
    ZshRC->>External: Initialize mise
    ZshRC->>External: Load private config (~/.localrc)
    
    External-->>User: Ready for use
```

### Bootstrap Installation Flow

```mermaid
sequenceDiagram
    participant User
    participant Bootstrap as script/bootstrap
    participant Git
    participant Symlink as SymlinkManager
    participant Dot as bin/dot
    participant Homebrew

    User->>Bootstrap: ./script/bootstrap
    
    Bootstrap->>Git: setup_gitconfig()
    Note over Git: Prompt for name/email<br/>Create gitconfig.local.symlink
    
    Bootstrap->>Symlink: install_dotfiles()
    loop For each *.symlink file
        Symlink->>Symlink: Check if file exists
        alt File exists
            Symlink->>User: Prompt for action
            User-->>Symlink: [s]kip/[o]verwrite/[b]ackup
        end
        Symlink->>Symlink: Create symlink
    end
    
    Note over Bootstrap: If macOS detected
    Bootstrap->>Dot: Run dependency installation
    Dot->>Homebrew: Install/update packages
    Dot->>Dot: Run all install scripts
    Dot-->>Bootstrap: Installation complete
    
    Bootstrap-->>User: Setup complete!
```

## File Organization

### Directory Structure

```
~/.dotfiles/
├── 📁 Core System Files
│   ├── script/
│   │   ├── bootstrap          # First-time setup
│   │   └── install           # Run all installers
│   ├── bin/
│   │   ├── dot               # Update system
│   │   └── git-*             # Git utilities
│   ├── Brewfile              # Homebrew packages
│   └── README.md
│
├── 📁 Configuration Topics
│   ├── git/
│   │   ├── gitconfig.symlink     # → ~/.gitconfig
│   │   ├── gitconfig.local.symlink.example
│   │   ├── aliases.zsh           # Git aliases
│   │   └── completion.zsh        # Git completions
│   │
│   ├── zsh/
│   │   ├── zshrc.symlink         # → ~/.zshrc (main loader)
│   │   ├── config.zsh            # Zsh configuration
│   │   ├── prompt.zsh            # Custom prompt
│   │   ├── completion.zsh        # General completions
│   │   ├── fpath.zsh            # Function path setup
│   │   └── window.zsh           # Terminal title
│   │
│   ├── code/
│   │   ├── settings.json         # → ~/.../Code/User/
│   │   ├── keybindings.json      # → ~/.../Code/User/
│   │   ├── install.sh            # Extension installer
│   │   └── path.zsh             # Add code to PATH
│   │
│   ├── mise/
│   │   ├── mise.toml.symlink     # → ~/.mise.toml
│   │   ├── mise.zsh             # Mise initialization
│   │   ├── install.sh           # Runtime installation
│   │   └── completion.zsh       # Mise completions
│   │
│   └── [other topics]/
│
├── 📁 Extended Features
│   ├── claude/
│   │   ├── agents/              # AI agent definitions
│   │   ├── commands/            # Custom commands
│   │   ├── install.sh           # Claude setup
│   │   └── aliases.zsh          # Claude shortcuts
│   │
│   └── functions/
│       ├── c                    # Directory jumping
│       ├── extract              # Archive extraction
│       └── _*                   # Completion functions
```

### File Types and Their Purposes

| Pattern | Purpose | Example | Destination | Loading Order |
|---------|---------|---------|-------------|---------------|
| `*.symlink` | Files to link to home directory | `gitconfig.symlink` | `~/.gitconfig` | During bootstrap |
| `path.zsh` | PATH modifications | Add `/usr/local/bin` | Shell PATH | 1st (earliest) |
| `env.zsh` | Environment variables | `export VAR="value"` | Shell environment | 2nd |
| `aliases.zsh` | Command aliases | `alias ll='ls -la'` | Shell aliases | 2nd |
| `*.zsh` | Other shell configuration | Functions, settings | Shell environment | 2nd |
| `completion.zsh` | Shell completions | Command completions | Zsh completion system | 3rd (last) |
| `install.sh` | Installation scripts | Install packages | System setup | During install |

### Naming Consistency Requirements

**Strict Naming Convention** (must be exact):
- `install.sh` - Installation script for the topic
- `path.zsh` - PATH modifications (loaded first)
- `aliases.zsh` - Command aliases
- `env.zsh` - Environment variables
- `completion.zsh` - Shell completions (loaded last)
- `*.symlink` - Files to be symlinked to home directory

**Ignored Patterns**:
- Folders starting with `_` (e.g., `_docs/`, `_archive/`, `_private/`)
- Files starting with `_` in any folder
- `.git` directory and all its contents

**Special Cases** (non-standard handling):
- `ssh/config` - Symlinked to `~/.ssh/config` by install.sh (special location)
- `ghostty/config` - Symlinked to Ghostty's app support by install.sh
- `code/settings.json` & `code/keybindings.json` - Copied to VS Code config location
- `macos/set-defaults.sh` & `macos/set-hostname.sh` - Must keep exact names, called by `macos/install.sh`
  - The wrapper prevents duplicate execution (previously called directly by `bin/dot`)
- `git/gitconfig.local.symlink` - Generated by bootstrap, not stored in repo

## Extension Points

### Adding New Topics

1. **Create Topic Directory**
   ```bash
   mkdir ~/.dotfiles/newtopic
   ```

2. **Add Configuration Files**
   ```bash
   # Shell configuration
   echo "# New topic config" > newtopic/config.zsh
   
   # PATH additions
   echo 'export PATH="$PATH:/new/path"' > newtopic/path.zsh
   
   # Aliases
   echo 'alias nt="newtopic-command"' > newtopic/aliases.zsh
   ```

3. **Create Installation Script**
   ```bash
   cat > newtopic/install.sh << 'EOF'
   #!/bin/sh
   echo "Installing newtopic..."
   
   if [ "$(uname -s)" = "Darwin" ]; then
     brew install newtopic-package
   fi
   EOF
   chmod +x newtopic/install.sh
   ```

4. **Add Symlink Files**
   ```bash
   # Configuration that goes to home directory
   echo "config content" > newtopic/config.symlink  # → ~/.config
   ```

### Hooks and Integration Points

```bash
# ~/.localrc - Private configuration (gitignored)
export PRIVATE_API_KEY="secret"
source ~/.custom-config

# ~/.gitconfig.local - Private git config (gitignored) 
[user]
    name = Your Name
    email = your@email.com

# ~/.dotfiles/ssh/config_local - Private SSH config
Host private-server
    HostName 192.168.1.100
    User admin
```

### Custom Functions and Utilities

```bash
# Add to any topic's *.zsh file
function my_custom_function() {
    echo "Custom functionality"
}

# Or create dedicated function file
# ~/.dotfiles/functions/my_function
function my_function() {
    # Implementation
}
```

## Security Model

### Sensitive Data Handling

```mermaid
graph TD
    subgraph "Public Repository"
        PublicConfigs[Public Configurations]
        Templates[*.example files]
        Scripts[Installation Scripts]
    end
    
    subgraph "Local Machine"
        PrivateConfigs[Private Configurations]
        Secrets[Secrets & Keys]
        LocalRC[~/.localrc]
        GitLocal[~/.gitconfig.local]
    end
    
    subgraph "External Services"
        Bitwarden[Bitwarden Vault]
        GitHub[GitHub Keys]
        SSH[SSH Keys]
    end
    
    PublicConfigs --> Templates
    Templates --> PrivateConfigs
    PrivateConfigs --> LocalRC
    PrivateConfigs --> GitLocal
    
    Scripts --> Bitwarden
    Scripts --> GitHub
    Scripts --> SSH
    
    style PrivateConfigs fill:#ff9999
    style Secrets fill:#ff6666
    style LocalRC fill:#ff6666
    style GitLocal fill:#ff6666
```

### File Permissions

```bash
# SSH configuration
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/id_*.pub

# Private configuration files
chmod 600 ~/.localrc
chmod 600 ~/.gitconfig.local

# Installation scripts
chmod +x ~/.dotfiles/*/install.sh
chmod +x ~/.dotfiles/script/*
chmod +x ~/.dotfiles/bin/*
```

## Performance Considerations

### Shell Startup Optimization

1. **Lazy Loading**: Heavy tools initialized only when needed
   ```bash
   # Instead of: eval "$(mise activate zsh)"
   # Use conditional loading:
   if (( $+commands[mise] )); then
     eval "$(mise activate zsh)"
   fi
   ```

2. **Completion Loading**: Completions loaded last to avoid blocking
   ```bash
   # In zshrc.symlink
   # 1. Load paths first (fast)
   # 2. Load configs (medium)  
   # 3. Load completions last (slow)
   ```

3. **Function Definition**: Define functions instead of running commands
   ```bash
   # Good: Define function for later use
   function docker_cleanup() {
     docker system prune -f
   }
   
   # Avoid: Running expensive commands at shell start
   # docker system prune -f  # Don't do this
   ```

### Installation Performance

1. **Parallel Installation**: Where possible, run installers in parallel
2. **Idempotent Scripts**: Scripts can be run multiple times safely
3. **Dependency Checking**: Skip installation if already present
4. **Progress Feedback**: Provide user feedback for long operations

### Memory Usage

```bash
# Monitor shell memory usage
ps -o pid,ppid,rss,vsz,comm -p $$

# Profile zsh startup time  
time zsh -i -c exit

# Identify slow loading components
zsh -x -i -c exit 2>&1 | grep -E '^\+'
```

---

This architecture provides a solid foundation for maintaining a scalable, secure, and performant development environment configuration system.