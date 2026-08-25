<div align="center">

# dotfiles

Personal, reproducible macOS setup for software development, operations, and
infrastructure work.

[Install](#install-on-a-new-mac) · [Update](#keep-the-machine-current) ·
[Software](#software-catalog) · [Commands](#public-commands) ·
[Architecture](#how-the-repository-works) · [Validation](#validation)

</div>

This repository declares applications, command-line tools, language runtimes,
macOS preferences, Zsh behavior, and application configuration. A single
bootstrap configures a new Mac; the `dot` command keeps an existing machine in
sync with the declarations.

> [!WARNING]
> These are personal dotfiles, not a universal macOS installer. Review the
> repository before applying it: bootstrap installs software, changes macOS
> preferences, and links configuration into your home directory.

## What this repository manages

- Homebrew taps, formulae, casks, fonts, and Xcode from the Mac App Store.
- Language runtimes and globally installed language-package CLIs through Mise.
- Deterministic, worktree-aware linking of dotfiles and application config.
- Idempotent topic installers for Git, Zsh, editors, terminal tools, SSH, SOPS,
  OpenCode/OCX, and macOS applications.
- A private-machine boundary for credentials and account-specific settings.
- Fixture-based tests for setup, linking, shell startup, package contracts, and
  application provisioning.

## Install on a new Mac

### Requirements

- macOS
- Git
- Xcode Command Line Tools
- Internet access for Homebrew, Mise, and declared packages

Install the command-line tools, clone the repository to the conventional path,
and run bootstrap:

```bash
xcode-select --install
git clone https://github.com/danilomartinelli/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
_scripts/bootstrap
```

Bootstrap performs the complete first-machine workflow:

1. Creates `.localrc` from the secret-free `.localrc.example` template and
   restricts it to mode `600`.
1. Prompts for the Git author name and email only when the private
   `git/gitconfig.local.symlink` does not exist.
1. Links `.localrc`, root-level `*.symlink` entries, topic `*.symlink` entries,
   and the worktree-aware `~/.dotfiles-root` resolver.
1. Applies the tracked macOS defaults and attempts hostname normalization.
1. Installs Homebrew and reconciles every declaration in `Brewfile`.
1. Runs each discovered topic installer in deterministic order.

Existing destinations are never replaced silently. Interactive bootstrap lets
you skip, overwrite, or back up a conflict. Topic installers remain
non-interactive and use explicit preservation or backup policies.

> [!IMPORTANT]
> Bootstrap and normal updates do not open graphical applications, recover
> credentials, or reset Keychain state. Application sign-in remains manual.

After installation, open a new terminal or load the new shell configuration:

```bash
source ~/.zshrc
```

To print the post-install checklist and intentionally open the listed apps, use
an interactive terminal:

```bash
_scripts/setup checklist --open-apps
```

SSH and SOPS installers never invent credentials. Create keys only through the
explicit commands when needed:

```bash
ssh-key-create default
ssh-key-create personal
ssh-key-create work
ssh-key-create work --rsa

sops-key-create default
sops-key-create personal
sops-key-create work
```

## Keep the machine current

Run the public update command:

```bash
dot
```

`dot` repairs the checkout-root link, attempts `git pull`, restores a missing
private environment file from its template, conservatively recreates missing
dotfile links, updates Homebrew, reconciles `Brewfile`, and reruns topic
installers. Checkout refresh and Homebrew update/upgrade are advisory; declared
dependency and installer failures stop the run.

Unlike first bootstrap, an update does not prompt for Git identity or reapply
macOS defaults.

| Command                           | Purpose                                                           |
| --------------------------------- | ----------------------------------------------------------------- |
| `dot`                             | Update the checkout, dependencies, links, and topic configuration |
| `dot --edit`                      | Open the active physical checkout in `$EDITOR`                    |
| `dot --help`                      | Print supported lifecycle options                                 |
| `_scripts/bootstrap`              | Run the complete first-machine installation                       |
| `_scripts/setup bootstrap`        | Invoke the canonical bootstrap implementation                     |
| `_scripts/setup update`           | Invoke the canonical daily-update implementation                  |
| `dotfiles-root.symlink --install` | Repair `~/.dotfiles-root` for this checkout                       |
| `set-defaults`                    | Explicitly reapply tracked macOS preferences                      |

## Software catalog

`Brewfile` is the source of truth for system packages and applications.
`mise/config.toml` declares language runtimes and language-distributed CLIs;
`mise/mise.lock` pins their resolved versions and checksums.

### Homebrew command-line tools

| Formula                   | Purpose                                          |
| ------------------------- | ------------------------------------------------ |
| `age`                     | Encryption backend used by SOPS identities       |
| `ansible`                 | Automation and configuration management          |
| `atuin`                   | SQLite-backed shell history with optional sync   |
| `aws-vault`               | Keychain-backed AWS credentials and SSO sessions |
| `awscli`                  | AWS command-line interface                       |
| `bat`                     | Syntax-highlighting `cat` replacement            |
| `bitwarden-cli`           | Bitwarden command-line client                    |
| `btop`                    | Process and resource monitor                     |
| `cocoapods`               | Cocoa dependency manager for iOS/macOS projects  |
| `coreutils`               | GNU core utilities, including `gls` and `gdate`  |
| `defaultbrowser`          | Inspect or change the macOS default browser      |
| `direnv`                  | Directory-specific environment loading           |
| `dockutil`                | Programmatic Dock configuration                  |
| `duti`                    | Default application associations                 |
| `eza`                     | Modern `ls` replacement                          |
| `fd`                      | Modern `find` replacement                        |
| `fzf`                     | Command-line fuzzy finder                        |
| `gawk`                    | GNU awk                                          |
| `gh`                      | GitHub CLI                                       |
| `git`                     | Version control                                  |
| `git-delta`               | Syntax-highlighting Git pager                    |
| `git-lfs`                 | Git Large File Storage                           |
| `gitleaks`                | Secret scanner                                   |
| `go-task`                 | Project task runner                              |
| `glab`                    | GitLab CLI                                       |
| `gnu-sed`                 | GNU sed as `gsed`                                |
| `grc`                     | Colorized output for common commands             |
| `helm`                    | Kubernetes package manager                       |
| `helmfile`                | Declarative Helm release management              |
| `hermes-agent`            | Hermes Agent CLI                                 |
| `imagemagick`             | Image conversion and manipulation                |
| `jq`                      | JSON processor                                   |
| `k9s`                     | Kubernetes terminal UI                           |
| `ksops`                   | SOPS integration for Kustomize                   |
| `kubectx`                 | Kubernetes context and namespace switchers       |
| `kubernetes-cli`          | `kubectl`                                        |
| `kustomize`               | Kubernetes manifest customization                |
| `vultr-cli`               | Vultr and VKE command-line client                |
| `lazygit`                 | Git terminal UI                                  |
| `mas`                     | Mac App Store CLI                                |
| `mise`                    | Runtime and tool version manager                 |
| `mkcert`                  | Locally trusted development certificates         |
| `neovim`                  | Terminal editor                                  |
| `nixfmt`                  | Nix formatter                                    |
| `pandoc`                  | Document converter                               |
| `python@3.12`             | Python runtime required by Aider                 |
| `ripgrep`                 | Fast recursive text search                       |
| `sops`                    | Secrets encryption with age, KMS, or PGP         |
| `spaceman-diff`           | Visual image diffs                               |
| `stern`                   | Multi-pod Kubernetes log tailing                 |
| `tmux`                    | Terminal multiplexer                             |
| `psviderski/tap/uncloud`  | Uncloud deployment CLI (`uc`)                    |
| `usage`                   | Usage-spec support for CLI completions           |
| `watch`                   | Periodically rerun a command                     |
| `watchexec`               | Rerun commands on file changes                   |
| `watchman`                | Filesystem watcher                               |
| `wget`                    | File downloader                                  |
| `xh`                      | Friendly terminal HTTP client                    |
| `yq`                      | YAML, TOML, and XML processor                    |
| `zoxide`                  | Smarter directory navigation                     |
| `zsh-autosuggestions`     | Fish-like Zsh suggestions                        |
| `zsh-syntax-highlighting` | Zsh command-line highlighting                    |

Third-party taps are declared in `Brewfile`. `homebrew/_bundle.sh` maintains a
narrow trust list for `nikitabobko/tap`, `psviderski/tap`, and
`vultr/vultr-cli` before running `brew bundle`.

### Applications and fonts

| Group                     | Homebrew casks                                                                                              |
| ------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Development               | `android-studio`, `chatgpt`, `lens`, `linear`, `postman`, `tableplus`, `zed`                                |
| Terminal and AWS          | `ghostty`, `session-manager-plugin`                                                                         |
| Window and menu bar       | `nikitabobko/tap/aerospace`, `bartender`, `keyclu`                                                          |
| Browsers and productivity | `archiver-app`, `caffeine`, `thebrowsercompany-dia`, `google-drive`, `obsidian`, `paste`, `raycast`, `skim` |
| Design and media          | `cleanshot`, `figma`, `spotify`                                                                             |
| Communication             | `discord`, `readdle-spark`, `slack`, `whatsapp`                                                             |
| Network and security      | `bitwarden`, `tailscale-app`, `yubico-authenticator`                                                        |
| Runtime and containers    | `orbstack`                                                                                                  |
| Fonts                     | `font-jetbrains-mono-nerd-font`                                                                             |

The Mac App Store declaration is `Xcode` (app id `497799835`).

Topic installers configure Ghostty, Zed, Neovim, AeroSpace, OrbStack,
Bartender, KeyClu, Raycast script commands, Tailscale, OpenCode/OCX, Hermes,
SOPS directories, SSH, Workspace, Mise, Archiver associations, and the Dock.
The declared Dock layout is applied once so later manual changes survive;
`DOTFILES_DOCK_RESET=1 dot` opts into reapplying it.

### Mise runtimes and global CLIs

Versions may be floating declarations such as `latest`, `lts`, or a minor
series. Reproducibility comes from the generated `mise/mise.lock`. Run
`mise install` to reconcile the lock and `mise upgrade` to advance it
deliberately.

| Tool                                        | Declared version | Role                                            |
| ------------------------------------------- | ---------------- | ----------------------------------------------- |
| `aqua:koalaman/shellcheck`                  | `latest`         | Shell linting                                   |
| `bun`                                       | `1.3.2`          | JavaScript runtime and package manager          |
| `elixir`                                    | `1.18`           | Elixir runtime                                  |
| `erlang`                                    | `28`             | BEAM runtime                                    |
| `go`                                        | `1.25.5`         | Go toolchain                                    |
| `go:mvdan.cc/sh/v3/cmd/shfmt`               | `latest`         | Shell formatting                                |
| `java`                                      | `temurin-21`     | Java runtime                                    |
| `node`                                      | `lts`            | Node.js LTS                                     |
| `npm:@anthropic-ai/claude-code`             | `2.1.223`        | Claude Code CLI                                 |
| `npm:@agentclientprotocol/claude-agent-acp` | `0.65.0`         | Claude ACP agent                                |
| `npm:@agentclientprotocol/codex-acp`        | `1.1.13`         | Codex ACP agent                                 |
| `npm:@earendil-works/pi-coding-agent`       | `0.84.0`         | Pi coding agent                                 |
| `npm:@colbymchenry/codegraph`               | `1.5.0`          | Repository code graph CLI                       |
| `npm:@openai/codex`                         | `0.146.1`        | Codex CLI                                       |
| `npm:eas-cli`                               | `16.28.0`        | Expo Application Services CLI                   |
| `npm:neonctl`                               | `3.6.0`          | Neon CLI                                        |
| `npm:ocx`                                   | `2.0.15`         | OpenCode extension and profile manager          |
| `npm:opencode-ai`                           | `1.18.23`        | OpenCode CLI                                    |
| `npm:skills`                                | `1.5.21`         | Agent skills CLI                                |
| `npm:wrangler`                              | `4.119.0`        | Cloudflare Workers CLI                          |
| `pipx:aider-chat`                           | `0.86.2`         | Aider coding assistant                          |
| `pipx:kimi-cli`                             | `1.49.0`         | Kimi CLI                                        |
| `pipx:mdformat`                             | `latest`         | Markdown formatter with GFM/frontmatter plugins |
| `pnpm`                                      | `10.23.0`        | JavaScript package manager                      |
| `python`                                    | `3.14.0`         | Python runtime                                  |
| `ruby`                                      | `3.4`            | Ruby runtime                                    |
| `rust`                                      | `1.91.1`         | Rust toolchain                                  |
| `terraform`                                 | `1.14.0`         | Infrastructure as code CLI                      |
| `uv`                                        | `latest`         | Python package and environment manager          |
| `yarn`                                      | `4.11.0`         | JavaScript package manager                      |

Generated `.codegraph/` and `.wrangler/` directories are machine-local and
must not be committed.

## Public commands

`bin/` is added to `PATH`. Executables named `git-*` can be called directly or
through their preferred Git subcommand form.

### General utilities

| Command           | Usage and purpose                                                 |
| ----------------- | ----------------------------------------------------------------- |
| `battery-status`  | Print the macOS battery indicator used by the prompt              |
| `dns-flush`       | Flush the macOS DNS cache with `sudo`                             |
| `dot`             | Run normal dotfiles maintenance                                   |
| `e`               | `e [path]`: open a path or the current directory in `$EDITOR`     |
| `headers`         | `headers URL`: print HTTP response headers                        |
| `keyclu-import`   | Open the tracked KeyClu shortcut collection for import            |
| `nix-install`     | Explicitly install Nix; never runs during bootstrap or `dot`      |
| `set-defaults`    | Apply tracked macOS preferences                                   |
| `sops-key-create` | `sops-key-create <role>`: create a non-overwriting age identity   |
| `ssh-key-create`  | `ssh-key-create <role> [--rsa]`: create a non-overwriting SSH key |

### Git utilities

| Executable                | Preferred invocation and purpose                                          |
| ------------------------- | ------------------------------------------------------------------------- |
| `git-all`                 | `git all`: stage every change                                             |
| `git-amend`               | `git amend`: amend while preserving the commit message                    |
| `git-copy-branch-name`    | `git copy-branch-name`: copy the current branch name                      |
| `git-credit`              | `git credit "Name" email`: add another author to the last commit          |
| `git-delete-local-merged` | `git delete-local-merged`: remove merged local branches safely            |
| `git-edit-new`            | `git edit-new`: open untracked files in `$EDITOR`                         |
| `git-nuke`                | `git nuke branch`: force-delete a local and matching remote branch        |
| `git-promote`             | `git promote`: push and track the current branch                          |
| `git-rank-contributors`   | `git rank-contributors [-v] [-o] [-h]`: rank authors by changed lines     |
| `git-track`               | `git track`: track the matching branch on `origin`                        |
| `git-undo`                | `git undo`: soft-reset the latest commit                                  |
| `git-unpushed`            | `git unpushed`: inspect commits not present on the matching remote branch |
| `git-unpushed-stat`       | `git unpushed-stat`: summarize the unpushed diff and commit count         |
| `git-up`                  | `git up [pull options]`: pull and list received commits                   |
| `git-wtf`                 | `git wtf [options]`: summarize branch relationships                       |

> [!CAUTION]
> `git nuke` changes local and remote state. `git credit`, `git amend`, and
> `git undo` rewrite local history. Inspect the target before using them.

## Zsh functions and aliases

`functions/` is added to Zsh `fpath`. Files without a leading underscore are
public autoload functions; underscore-prefixed files are internal completion
implementations.

| Function  | Usage and purpose                                                  |
| --------- | ------------------------------------------------------------------ |
| `c`       | `c [project]`: enter `$PROJECTS/project`                           |
| `extract` | Extract common archive formats or mount a `.dmg` on macOS          |
| `gf`      | `gf remote-branch`: switch locally or track `origin/remote-branch` |
| `pi`      | `pi [args...]`: invoke the Pi coding agent                         |
| `pubkey`  | Copy the default SSH public key, preferring Ed25519                |

Arguments provided after an alias are passed to the expanded command.

| Area                      | Aliases                                                                                                                              |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Shell                     | `reload!`, `cls`, `grep`                                                                                                             |
| Files                     | `ls`, `l`, `ll`, `la`, `lt`, `cat`                                                                                                   |
| Editor                    | `v`, `vi`, `vim`, `vimrc`                                                                                                            |
| Homebrew                  | `bi`, `bu`, `bug`, `bs`, `binfo`, `brews`, `brewsc`                                                                                  |
| Mise                      | `m`, `mi`, `mu`, `ml`, `mc`                                                                                                          |
| Aider                     | `aider-architect`, `aider-ro`                                                                                                        |
| Obsidian                  | `obs`                                                                                                                                |
| Hermes                    | `hermes-model`, `hermes-setup`, `hermes-doctor`, `hermes-update`                                                                     |
| Homelab                   | `hl`, `hlup`, `hldoctor`, `hllog`, `hlbootstrap`                                                                                     |
| Docker                    | `d`, `dc`, `dps`, `dpsa`, `dimg`, `dex`, `dlog`, `dlogf`, `dctx`, `dcu`, `dcd`, `dcl`                                                |
| tmux                      | `ta`, `tls`, `tn`, `tk`, `t`                                                                                                         |
| Mobile                    | `android`, `android_devices`, `ios`, `ios_devices`, `rn`, `rni`, `rna`, `pods`                                                       |
| Tailscale                 | `ts`, `tsstatus`, `tsip`, `tsup`, `tsdown`, `tsping`                                                                                 |
| SOPS                      | `sops-encrypt`, `sops-decrypt`, `sops-decrypt-inplace`, `sops-edit`, `sops-env`, `sops-run`                                          |
| SSH                       | `sshclean`                                                                                                                           |
| Git                       | `g`, `gl`, `glog`, `gp`, `gpf`, `gd`, `gc`, `gca`, `gcm`, `gco`, `gsw`, `gcb`, `gb`, `gs`, `gac`, `ge`, `grb`, `gcp`, `gsta`, `gstp` |
| Kubectl context           | `k`, `kctx`, `kctx-list`, `kcurrent`, `konfig`, `kns`                                                                                |
| Kubectl resources         | `kgp`, `kgpa`, `kgs`, `kgsa`, `kgd`, `kgda`, `kgn`, `kgns`                                                                           |
| Kubectl operations        | `kdp`, `kds`, `kdd`, `kdn`, `kl`, `klf`, `klt`, `kaf`, `kdf`, `kex`, `kpf`, `kwp`, `kwpa`                                            |
| AWS basics/output         | `awsl`, `awswho`, `awsregion`, `awsjson`, `awstable`, `awstext`, `awscost`                                                           |
| AWS profiles/SSO          | `awsp`, `awssso`, `awslogout`, `av`                                                                                                  |
| AWS S3                    | `s3ls`, `s3cp`, `s3mv`, `s3rm`, `s3sync`, `s3mb`, `s3rb`, `s3web`                                                                    |
| AWS EC2                   | `ec2ls`, `ec2start`, `ec2stop`, `ec2reboot`, `ec2terminate`, `ec2ip`                                                                 |
| AWS Lambda/CloudFormation | `lambdals`, `lambdainvoke`, `lambdalogs`, `lambdadeploy`, `cfnls`, `cfnvalidate`, `cfnevents`, `cfnoutputs`                          |
| AWS ECS/RDS               | `ecsls`, `ecsservices`, `ecstasks`, `ecsdescribe`, `rdsls`, `rdsstart`, `rdsstop`                                                    |
| AWS IAM/SSM               | `iamusers`, `iamroles`, `iamgroups`, `iampolicies`, `ssmls`, `ssmget`, `ssmput`, `ssmsession`                                        |
| AWS CloudWatch/DynamoDB   | `cwlogs`, `cwtail`, `cwalarms`, `dynamols`, `dynamoscan`, `dynamoquery`                                                              |

OpenCode is launched through OCX: `opencode` and `oc` use the `regular`
profile selected by `OCX_PROFILE`; `oc:regular`, `oc:go`, and `oc:boost`
select a profile explicitly.

## How the repository works

### Topic architecture

```text
dotfiles/
├── bin/                    # Public executables
├── functions/              # Public autoload functions
├── tests/                  # Fixture-based repository tests
├── _scripts/               # Private setup and linking machinery
├── _macos/                 # macOS defaults implementation
├── topic/
│   ├── install.sh          # Optional idempotent installer
│   ├── *.symlink           # Home-directory link source
│   ├── path.zsh            # Loaded before other topic files
│   ├── aliases.zsh         # Main Zsh configuration
│   ├── env.zsh             # Main Zsh configuration
│   └── completion.zsh      # Loaded after compinit
├── Brewfile
├── dotfiles-root.symlink
└── .localrc.example
```

`_scripts/topic-catalog <repository-root>` is the single classifier used by
setup, Zsh startup, and documentation coverage. It emits deterministic
`kind<TAB>absolute-path` records for topics, links, installers, path files,
main Zsh files, the prompt, completions, and alias files.

Names beginning with `_` or `.` are private and excluded from discovery.
`bin/`, `functions/`, and `tests/` are visible but explicitly classified as
non-topics.

### Setup lifecycle

`_scripts/setup` owns orchestration:

- `bootstrap` creates private templates and identity, links dotfiles, applies
  macOS defaults, installs Homebrew declarations, and runs topic installers.
- `update` refreshes the checkout and links, updates Homebrew, reconciles
  declarations, and reruns topic installers without reapplying macOS defaults.
- `checklist --open-apps` is the only intentional graphical app-opening path.

`_scripts/bootstrap` and `bin/dot` are stable public adapters. Homebrew
availability, maintenance, and bundle reconciliation remain separate private
phases so failures have clear ownership.

### Zsh loading order

`zsh/zshrc.symlink` resolves the physical checkout and loads
`zsh/_startup.zsh` once. Startup then:

1. Loads optional `~/.localrc`, followed by tracked `.commonrc`.
1. Initializes Homebrew, unique `PATH`/`MANPATH`, functions, and topic paths.
1. Sources sorted `path.zsh` files, then other visible topic `*.zsh` files.
1. Loads `zsh/prompt.zsh` as the sole prompt implementation.
1. Runs `compinit` once and loads sorted completion files.
1. Loads optional syntax highlighting last.

Reloading is idempotent: paths, hooks, and implementation state remain
de-duplicated.

### Configuration ownership

| Configuration         | Installed location            | Ownership rule                                           |
| --------------------- | ----------------------------- | -------------------------------------------------------- |
| Private environment   | `~/.localrc`                  | Generated locally, mode `600`, never committed           |
| Shared shell defaults | `.commonrc`                   | Tracked and secret-free                                  |
| Git identity          | `git/gitconfig.local.symlink` | Generated locally and gitignored                         |
| Private SSH hosts     | `~/.ssh/config_local`         | Preserved by the tracked SSH config                      |
| SOPS age identities   | `~/.config/sops/age/`         | Machine-private, mode `600`                              |
| Zed settings          | `~/.config/zed/settings.json` | Tracked JSON, no plaintext credentials                   |
| OpenCode workspace    | `~/.config/opencode`          | Split between dotfiles-owned links and OCX runtime state |
| Hermes state          | `~/.hermes`                   | Machine-local runtime state                              |

Never place secrets in tracked JSON or simulate interpolation with
`$VARIABLE`: Zed treats such values literally in settings fields. Prefer OAuth
or a process-backed integration that reads inherited environment. Keep keys,
kubeconfigs, auth receipts, and account-specific state outside this repository.

### OpenCode and OCX

OpenCode is a Mise-managed CLI launched through OCX. The installer initializes
the `kdco` registry and links the dotfiles-owned `agents`, `commands`, `skills`,
`tools`, `ocx.jsonc`, `opencode.jsonc`, `tui.jsonc`, and the `regular`, `go`,
and `boost` profile directories. The managed TUI follows the terminal's
Catppuccin Macchiato theme and keeps audible notifications disabled. OCX retains
`.ocx`, generated `plugins`, `package.json`, `.gitignore`, and
`profiles/default`.

The `regular` profile carries the active trusted-project model and MCP policy.
The `go` and `boost` directories are managed profile slots and can specialize
that baseline without changing the default shell profile.

See [`opencode/README.md`](opencode/README.md) for profile maintenance,
ownership, verification, and troubleshooting.

## Validation

The test suites create isolated homes and fake external commands; they do not
apply configuration to the real Mac.

```bash
tests/setup_test.sh
tests/zsh_startup_test.sh
tests/ssh_provisioning_test.sh
tests/sops_provisioning_test.sh
tests/git_branch_state_test.sh
tests/homebrew_availability_test.sh
tests/homebrew_bundle_test.sh
tests/homebrew_maintenance_test.sh
tests/archiver_install_test.sh
tests/link_config_test.sh
tests/link_dotfiles_test.sh
tests/installer_preamble_test.sh
tests/macos_defaults_test.sh
tests/documentation_test.sh
tests/topic_catalog_test.sh
tests/opencode_install_test.sh
_scripts/test-checkout-root
```

`tests/documentation_test.sh` ensures that every public `bin/` command, Zsh
function, alias, Homebrew declaration, Mise tool, and installer helper remains
documented. Run the focused suite for a change first, then the complete suite
for repository-wide work.

Static checks used by this repository include:

```bash
zsh -n path/to/file.zsh
shellcheck path/to/script.sh
shfmt -d -i 2 -ci -bn path/to/script.sh
mdformat --check path/to/document.md
git diff --check
```

The Mise-managed `mdformat` includes the GFM and frontmatter plugins required
to preserve tables and skill metadata.

## Extend the setup

### Add a topic

1. Create a visible top-level directory that does not use a reserved name.
1. Add only the files the topic needs: `install.sh`, `*.symlink`, `path.zsh`,
   `aliases.zsh`, `env.zsh`, or `completion.zsh`.
1. Make `install.sh` executable, non-interactive, and idempotent.
1. Use `_scripts/installer-preamble.sh` for guards, output, and links.
1. Add fixture coverage and update this README for any public surface.

### Add a dependency

- Add system packages, applications, fonts, and taps to `Brewfile`.
- Add language-package CLIs and runtimes to `mise/config.toml`, regenerate the
  lock from the repository root, and review the generated diff.
- Update the software catalog above; documentation coverage will report any
  missing declaration.

Engineering contracts, safe editing rules, and delivery checks live in
[`GUIDELINES.md`](GUIDELINES.md). Agent-specific instructions live in
[`AGENTS.md`](AGENTS.md).
