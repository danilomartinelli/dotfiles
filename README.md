<div align="center">

# dotfiles

Personal, declarative macOS setup for software development, operations, and
infrastructure work.

[![CI](https://github.com/danilomartinelli/dotfiles/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/danilomartinelli/dotfiles/actions/workflows/ci.yml?query=branch%3Amain+event%3Apush)

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
  coding agents, and macOS applications.
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

The `xcode` and `android-studio` topic installers perform local-only mobile
runtime checks during bootstrap and updates. Missing runtimes produce an
actionable `mobile-setup` warning; normal setup never downloads runtimes,
accepts licenses, opens an app, or boots a device.

Existing destinations are never replaced silently. Interactive bootstrap lets
you skip, overwrite, or back up a conflict. Topic installers remain
non-interactive and select an explicit conflict policy: keep the existing file,
back it up, or, for a path its tool regenerates on every run, replace it and
report the replacement.

Backing up uses one `.backup` slot per destination. When that slot already holds
an earlier backup, the link cannot be made, so the run stops and names both
paths instead of reporting a link it never created. Move or remove the named
backup and rerun.

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

The checklist is declared in `_scripts/_checklist.tsv`. Its app column is the
single owner of both what that command opens and what the printed list calls
opened, so edit a row there rather than `_scripts/setup`. A row may name
several `|`-separated application paths in preference order: the first one
installed is the one opened, and a row with none installed is printed as not
installed rather than as one that opens.

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
dotfile links, updates Homebrew, reconciles `Brewfile` without blanket upgrades,
and reruns topic installers. It then reports available upgrades for declared
software and opens an interactive picker. Checkout refresh, Homebrew refresh,
and optional upgrade failures warn and continue; declared dependency and
installer failures stop the run.

Use Tab or Space to select packages, Ctrl-A to select all, and Enter to review
the selection. The final `Apply selected upgrades? [y/N]` confirmation defaults
to no. Escape cancels. Without an interactive terminal, `dot` reports candidates
and advisory vulnerability results but does not apply newly discovered releases.
If `fzf` is unavailable, selection is skipped with an actionable warning.

The picker includes declared Homebrew formulae, casks, App Store apps, and Mise
tools. Formulae held with `brew pin` are left out. Packages installed outside
the declarations are not independent upgrade targets, although selected packages
or newly installed declarations can require dependency changes. Homebrew itself
and its catalog are refreshed before selection. Apps may also update themselves
outside this flow; this repository does not disable their own updaters.

Versions already committed to the Mise lock, including those received by
`git pull`, are applied before the picker. Selecting a new Mise release updates
the appropriate declaration, regenerates its lock, installs the selected tools,
and refreshes the README catalog. Review and commit that diff separately:
`dot` does not commit or push. Channels such as Node `lts`, Java `temurin-25`,
Erlang `29` and OpenCode `1` are retained; exact pins can advance across major
versions, which the picker highlights.
The Mise installer also checks the installed formatter plugins against their
pins and refreshes only mdformat when those versions differ.

Vulnerability checks only advise in this CLI flow; they are not a CI gate.
`brew vulns` checks declared installed formulae and their dependencies, reporting
skipped coverage. OSV queries cover direct npm/PyPI packages in the Mise lock and
their available candidates, not their transitive dependency trees. Casks, App
Store apps, formatter extras, other backends, and runtimes are explicitly outside
that scan. A failed query is reported as unavailable, never as a clean audit.
The package names and versions queried are sent to the public OSV service.

Candidates are checked again before applying. Mise prepares and validates its
source changes in a temporary directory; failed preparation or installation
leaves tracked declarations intact. A failed install may leave an inactive tool
copy. Package-manager operations are not a transaction: an earlier successful
upgrade is retained if a later one fails. Avoid running concurrent package
upgrades against the same Mac.

Unlike first bootstrap, an update does not prompt for Git identity or reapply
macOS defaults.

| Command                            | Purpose                                                           |
| ---------------------------------- | ----------------------------------------------------------------- |
| `dot`                              | Update the checkout, dependencies, links, and topic configuration |
| `dot --edit`                       | Open the active physical checkout in `$EDITOR`                    |
| `dot --help`                       | Print supported lifecycle options                                 |
| `_scripts/bootstrap`               | Run the complete first-machine installation                       |
| `_scripts/setup bootstrap`         | Invoke the canonical bootstrap implementation                     |
| `_scripts/setup update`            | Invoke the canonical daily-update implementation                  |
| `dotfiles-root.symlink --install`  | Repair `~/.dotfiles-root` for this checkout                       |
| `set-defaults`                     | Explicitly reapply tracked macOS preferences                      |
| `_scripts/render-software-catalog` | Rewrite the README software catalog from the declarations         |

## Software catalog

`Brewfile` is the source of truth for system packages and applications.
`mise/config.toml` declares language runtimes and language-distributed CLIs;
`mise/mise.lock` pins their resolved versions and checksums.

Mise installs the versions recorded in that lock. Homebrew preserves installed
packages during normal reconciliation and offers controlled upgrades, but a
new installation still uses its current catalog. The repository reproduces the
declared setup and configuration, not a frozen machine image. See the
[controlled-upgrade decision](docs/adr/0001-controlled-software-upgrades.md).

The tables below are rendered from those two files by
`_scripts/render-software-catalog`, so a name, a version, a group, or a catalog
description is written once, where the software is declared. Each entry's
trailing comment is its catalog description. Run the renderer after changing a
declaration; `tests/documentation_test.sh` fails while the catalog is out of
date.

Both files stay literal, one declaration per line: the catalog, the
documentation check and controlled upgrades all read them through
`_scripts/declared_software.py`, which refuses Brewfile conditionals or entry
options, and Mise declarations that span lines or list several versions. See the
[declaration-grammar decision](docs/adr/0002-read-declarations-as-closed-literal-grammars.md).

### Homebrew command-line tools

<!-- generated: homebrew-formulae -->

| Formula                   | Purpose                                                           |
| ------------------------- | ----------------------------------------------------------------- |
| `age`                     | Encryption backend used by SOPS identities                        |
| `ansible`                 | Automation and configuration management                           |
| `atuin`                   | SQLite-backed shell history with optional sync                    |
| `aws-vault`               | Keychain-backed AWS credentials and SSO sessions                  |
| `awscli`                  | AWS command-line interface                                        |
| `bat`                     | Syntax-highlighting `cat` replacement                             |
| `bitwarden-cli`           | Bitwarden command-line client                                     |
| `btop`                    | Process and resource monitor                                      |
| `cloudflared`             | Cloudflare Tunnel client for exposing local services              |
| `cocoapods`               | Cocoa dependency manager for iOS/macOS projects (React Native)    |
| `coreutils`               | GNU core utilities, including `gls` and `gdate`                   |
| `defaultbrowser`          | Inspect or change the macOS default browser                       |
| `direnv`                  | Directory-specific environment loading                            |
| `dockutil`                | Programmatic Dock configuration                                   |
| `duti`                    | Default application associations                                  |
| `eza`                     | Modern `ls` replacement                                           |
| `fastlane`                | iOS and Android deployment automation                             |
| `fd`                      | Modern `find` replacement                                         |
| `fzf`                     | Command-line fuzzy finder                                         |
| `gawk`                    | GNU awk                                                           |
| `gh`                      | GitHub CLI                                                        |
| `git`                     | Version control                                                   |
| `git-delta`               | Syntax-highlighting Git pager                                     |
| `git-lfs`                 | Git Large File Storage                                            |
| `gitleaks`                | Secret scanner                                                    |
| `go-task`                 | Project task runner                                               |
| `glab`                    | GitLab CLI                                                        |
| `gnu-sed`                 | GNU sed as `gsed`                                                 |
| `grc`                     | Colorized output for common commands                              |
| `helm`                    | Kubernetes package manager                                        |
| `helmfile`                | Declarative Helm release management                               |
| `hermes-agent`            | Hermes Agent CLI                                                  |
| `imagemagick`             | Image conversion and manipulation                                 |
| `jq`                      | JSON processor                                                    |
| `k9s`                     | Kubernetes terminal UI                                            |
| `ksops`                   | SOPS integration for Kustomize                                    |
| `kubectx`                 | Kubernetes context and namespace switchers (`kubectx`, `kubens`)  |
| `kubernetes-cli`          | `kubectl`                                                         |
| `kustomize`               | Kubernetes manifest customization                                 |
| `vultr-cli`               | Vultr and VKE command-line client                                 |
| `lazygit`                 | Git terminal UI                                                   |
| `mas`                     | Mac App Store CLI                                                 |
| `mise`                    | Runtime and tool version manager (successor to asdf)              |
| `mkcert`                  | Locally trusted development certificates                          |
| `neovim`                  | Terminal editor                                                   |
| `nixfmt`                  | Nix formatter                                                     |
| `pandoc`                  | Document converter                                                |
| `python@3.12`             | Python 3.12 runtime required by Aider (`aider-chat` needs < 3.13) |
| `ripgrep`                 | Fast recursive text search                                        |
| `sops`                    | Secrets encryption with age, KMS, or PGP                          |
| `spaceman-diff`           | Visual image diffs                                                |
| `stern`                   | Multi-pod Kubernetes log tailing                                  |
| `tmux`                    | Terminal multiplexer                                              |
| `psviderski/tap/uncloud`  | Uncloud deployment CLI (`uc`)                                     |
| `usage`                   | Usage-spec support for CLI completions                            |
| `watch`                   | Periodically rerun a command                                      |
| `watchexec`               | Rerun commands on file changes                                    |
| `watchman`                | Filesystem watcher                                                |
| `wget`                    | File downloader                                                   |
| `xh`                      | Friendly terminal HTTP client                                     |
| `yq`                      | YAML, TOML, and XML processor                                     |
| `zoxide`                  | Smarter directory navigation                                      |
| `zsh-autosuggestions`     | Fish-like Zsh suggestions                                         |
| `zsh-syntax-highlighting` | Zsh command-line highlighting                                     |

<!-- generated-end -->

Third-party taps are declared in `Brewfile`. `homebrew/_bundle.sh` maintains a
narrow trust list for `psviderski/tap` and `vultr/vultr-cli` before running
`brew bundle`.

### Applications and fonts

<!-- generated: homebrew-casks -->

| Group                     | Homebrew casks                                                                                                |
| ------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Development               | `android-studio`, `chatgpt`, `claude`, `conductor`, `lens`, `opencode-desktop`, `postman`, `tableplus`, `zed` |
| Terminal and AWS          | `ghostty`, `session-manager-plugin`                                                                           |
| Window and menu bar       | `bartender`, `keyclu`                                                                                         |
| Browsers and productivity | `archiver-app`, `caffeine`, `thebrowsercompany-dia`, `google-drive`, `obsidian`, `paste`, `raycast`, `skim`   |
| Design and media          | `cleanshot`, `figma`, `spotify`                                                                               |
| Communication             | `discord`, `readdle-spark`, `slack`, `whatsapp`                                                               |
| Network and security      | `bitwarden`, `tailscale-app`, `yubico-authenticator`                                                          |
| Runtime and containers    | `orbstack`                                                                                                    |
| Fonts                     | `font-jetbrains-mono-nerd-font`                                                                               |

<!-- generated-end -->

<!-- generated: mac-app-store -->

| Mac App Store app | App ID      | Purpose                                    |
| ----------------- | ----------- | ------------------------------------------ |
| `Xcode`           | `497799835` | Apple's integrated development environment |

<!-- generated-end -->

Topic installers configure Ghostty, Zed, Neovim, OrbStack, Bartender, KeyClu,
Raycast script commands, Tailscale, OpenCode, Claude Code, Codex, Kimi Code,
Conductor, direnv, Hermes, SOPS directories, SSH, Workspace, Mise, iOS Simulator
and Android Emulator readiness, Archiver associations, and the Dock.
The Dock layout is declared in `dock/_layout.tsv`, one row per entry, and the
file types each app claims are declared in `<topic>/_associations.tsv`. Both are
applied once so later manual changes survive: a Dock you rearranged and a
default application you set in Finder both outlive an update run. Editing a row
therefore takes effect on the next `DOTFILES_RESET=dock dot`,
`DOTFILES_RESET=archiver-associations dot`, `DOTFILES_RESET=skim-associations dot`,
or `DOTFILES_RESET=zed-associations dot`; `DOTFILES_RESET=all dot` re-arms every
run-once step.

### Mise runtimes and global CLIs

Versions may be floating declarations such as `latest`, `lts`, or a minor
series. Reproducibility comes from the generated `mise/mise.lock`, and `dot`
installs exactly what it records with `mise install --locked`. Reconciliation
does not rewrite it; only explicitly selected new releases change it.

`mise lock --global`, run from the checkout, is the one command that writes the
lock. The interactive updater runs it against staged copies for selected tools.
After changing a declaration manually, run it and commit the lock with the
declaration; until then `dot` stops at the Mise topic and names that command.
`mise lock --global --bump` advances the floating declarations deliberately. A
plain `mise install` or `mise upgrade` still writes the lock in a shape of its
own, and `mise lock --global` settles it again.

<!-- generated: mise-tools -->

| Tool                                        | Declared version | Role                                            |
| ------------------------------------------- | ---------------- | ----------------------------------------------- |
| `aqua:koalaman/shellcheck`                  | `latest`         | Shell linting                                   |
| `bun`                                       | `1.3.9`          | JavaScript runtime and toolkit                  |
| `elixir`                                    | `1.20`           | Elixir runtime                                  |
| `erlang`                                    | `29`             | BEAM runtime                                    |
| `go`                                        | `1.27.1`         | Go toolchain                                    |
| `go:mvdan.cc/sh/v3/cmd/shfmt`               | `latest`         | Shell formatting                                |
| `java`                                      | `temurin-25`     | Java runtime                                    |
| `node`                                      | `lts`            | Node.js LTS                                     |
| `npm:@anthropic-ai/claude-code`             | `2.1.285`        | Claude Code CLI                                 |
| `npm:@agentclientprotocol/claude-agent-acp` | `0.84.0`         | Claude ACP agent                                |
| `npm:@agentclientprotocol/codex-acp`        | `2.1.0`          | Codex ACP agent                                 |
| `npm:@earendil-works/pi-coding-agent`       | `0.99.2`         | Pi coding agent                                 |
| `npm:@moonshot-ai/kimi-code`                | `2.1.1`          | Kimi Code CLI                                   |
| `npm:@colbymchenry/codegraph`               | `1.6.1`          | Repository code graph CLI                       |
| `npm:@swmansion/argent`                     | `0.26.0`         | Device and simulator control MCP                |
| `npm:@openai/codex`                         | `0.159.3`        | Codex CLI                                       |
| `npm:eas-cli`                               | `24.8.0`         | Expo Application Services CLI                   |
| `npm:neonctl`                               | `7.0.1`          | Neon CLI                                        |
| `npm:opencode-ai`                           | `1`              | OpenCode CLI                                    |
| `npm:skills`                                | `1.7.0`          | Agent skills CLI                                |
| `npm:wrangler`                              | `4.145.0`        | Cloudflare Workers CLI                          |
| `pipx:aider-chat`                           | `0.86.2`         | Aider coding assistant                          |
| `pipx:mdformat`                             | `latest`         | Markdown formatter with GFM/frontmatter plugins |
| `pnpm`                                      | `12.8.1`         | JavaScript package manager                      |
| `python`                                    | `3.14.7`         | Python runtime                                  |
| `ruby`                                      | `4.0`            | Ruby runtime                                    |
| `rust`                                      | `1.98.1`         | Rust toolchain                                  |
| `terraform`                                 | `1.16.4`         | Infrastructure as code CLI                      |
| `uv`                                        | `latest`         | Python package and environment manager          |
| `yarn`                                      | `4.18.1`         | JavaScript package manager                      |

<!-- generated-end -->

Generated `.codegraph/` and `.wrangler/` directories are machine-local and
must not be committed.

## Public commands

`bin/` is added to `PATH` ahead of Homebrew, so a package that ships a command
of the same name, such as Graphviz's `dot`, cannot shadow one of these.
Executables named `git-*` can be called directly or through their preferred Git
subcommand form.

### General utilities

| Command           | Usage and purpose                                                         |
| ----------------- | ------------------------------------------------------------------------- |
| `battery-status`  | Print the macOS battery indicator used by the prompt                      |
| `dns-flush`       | Flush the macOS DNS cache with `sudo`                                     |
| `dot`             | Run normal dotfiles maintenance                                           |
| `e`               | `e [path]`: open a path or the current directory in `$EDITOR`             |
| `headers`         | `headers URL`: print HTTP response headers                                |
| `keyclu-import`   | Open the tracked KeyClu shortcut collection for import                    |
| `mobile-setup`    | `mobile-setup [--check] [ios\|android\|all]`: provision mobile simulators |
| `nix-install`     | Explicitly install Nix; never runs during bootstrap or `dot`              |
| `set-defaults`    | Apply tracked macOS preferences                                           |
| `sops-key-create` | `sops-key-create <role>`: create a non-overwriting age identity           |
| `ssh-key-create`  | `ssh-key-create <role> [--rsa]`: create a non-overwriting SSH key         |

### Mobile simulator provisioning

`mobile-setup` is the explicit opt-in for heavy mobile runtime provisioning:

```bash
mobile-setup --check all
mobile-setup ios
mobile-setup android
```

`--check` is local-only and read-only. It exits successfully only when the
selected target is ready. The default target is `all`; `ios` and `android`
limit work to one platform.

The iOS path reads the selected full Xcode's iPhone Simulator SDK and skips the
download when an available matching runtime exists. Otherwise it asks Xcode for
the latest compatible runtime with `xcodebuild -downloadPlatform iOS`. Rerun the
check after an Xcode update.

The Android path uses only `$HOME/Library/Android/sdk`, with `ANDROID_HOME`
pointing at that root. It reconciles API 36 `google_apis` `arm64-v8a`, including
`platform-tools`, `emulator`, `cmdline-tools;latest`,
`platforms;android-36`, `build-tools;36.0.0`, and
`system-images;android-36;google_apis;arm64-v8a`. It creates the default
`Pixel_API36` AVD only when it is absent and selects an available Pixel hardware
profile. An incompatible existing AVD is never overwritten or deleted; the
command stops with a recovery instruction.

Vendor first-launch/setup-wizard work and Apple or Android license acceptance
remain manual. `mobile-setup` never pipes answers to license prompts, signs in,
opens an app, or boots an emulator.

### Git utilities

| Executable                | Preferred invocation and purpose                                          |
| ------------------------- | ------------------------------------------------------------------------- |
| `git-all`                 | `git all`: stage every change                                             |
| `git-amend`               | `git amend`: amend while preserving the commit message                    |
| `git-copy-branch-name`    | `git copy-branch-name`: copy the current branch name                      |
| `git-credit`              | `git credit "Name" email`: replace the author of the last commit          |
| `git-delete-local-merged` | `git delete-local-merged`: remove merged local branches safely            |
| `git-edit-new`            | `git edit-new`: open untracked files in `$EDITOR`                         |
| `git-nuke`                | `git nuke branch`: force-delete a local and matching remote branch        |
| `git-promote`             | `git promote`: publish a new branch and configure tracking                |
| `git-rank-contributors`   | `git rank-contributors [-v] [-o] [-h]`: rank authors by changed lines     |
| `git-track`               | `git track`: track the matching branch on `origin`                        |
| `git-undo`                | `git undo`: soft-reset the latest commit                                  |
| `git-unpushed`            | `git unpushed`: inspect commits not present on the matching remote branch |
| `git-unpushed-stat`       | `git unpushed-stat`: summarize the unpushed diff and commit count         |
| `git-up`                  | `git up [pull options]`: pull and list received commits                   |
| `git-wtf`                 | `git wtf [options]`: summarize branch relationships                       |

`git promote` pushes the current branch only when it does not exist on
`origin`. If it already exists, the command only configures tracking; use
`git push` to publish subsequent commits.

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

Arguments provided after an alias are passed to the expanded command. The Files
aliases are for a person's shell: Claude Code (`CLAUDECODE`) and Codex
(`CODEX_SHELL`) tool shells keep the standard `ls` and `cat`.

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
| Mobile                    | `android`, `android_devices`, `ios`, `ios_devices`, `rn`, `rni`, `rna`, `pods`, `fl`                                                 |
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
`bin/`, `docs/`, `functions/`, and `tests/` are visible but explicitly
classified as non-topics.

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

`zsh/zshenv.symlink` is linked as `~/.zshenv` and sets `LANG=en_US.UTF-8` and
`LC_MESSAGES=C` only when `__CFBundleIdentifier=com.conductor.app`. Conductor's
Git runner forwards the captured `LANG` to clean `zsh -f` shells, which skip
startup files and do not inherit `LC_MESSAGES`. Setting only `LC_MESSAGES`
therefore leaves the Git runner's missing-upstream error translated, and the
Changes panel can remain on "Loading git status..." until the branch has an
upstream. The workaround gives Conductor an English UTF-8 locale, preserving
explicit category overrides such as `LC_TIME`. Shells from other apps keep
their existing locale.

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

| Configuration          | Installed location             | Ownership rule                                                             |
| ---------------------- | ------------------------------ | -------------------------------------------------------------------------- |
| Private environment    | `~/.localrc`                   | Generated locally, mode `600`, never committed                             |
| Shared shell defaults  | `.commonrc`                    | Tracked and secret-free                                                    |
| Git identity           | `git/gitconfig.local.symlink`  | Generated locally and gitignored                                           |
| Git worktree overrides | `~/.gitconfig.worktree`        | Tracked; applied only to linked worktrees, above the machine-local include |
| Private SSH hosts      | `~/.ssh/config_local`          | Preserved by the tracked SSH config                                        |
| SOPS age identities    | `~/.config/sops/age/`          | Machine-private, mode `600`                                                |
| Zed settings           | `~/.config/zed/settings.json`  | Tracked JSONC-compatible config, no plaintext credentials                  |
| OpenCode config        | `~/.config/opencode`           | `opencode.jsonc` and `tui.jsonc` linked; the rest is OpenCode's own        |
| Claude Code settings   | `~/.claude/settings.json`      | Tracked; Claude Code's own writes land as a diff                           |
| Conductor settings     | `~/.conductor/settings.toml`   | Tracked; the Settings window's writes land as a diff                       |
| Kimi Code TUI settings | `~/.kimi-code/tui.toml`        | Tracked; `config.toml` holds credentials and stays machine-local           |
| Codex configuration    | `~/.codex/config.toml`         | Machine-local: Codex records project trust and plugin state in it          |
| direnv config          | `~/.config/direnv/direnv.toml` | Rendered locally from the trusted roots and gitignored                     |
| Hermes state           | `~/.hermes`                    | Machine-local runtime state                                                |

Never place secrets in tracked configuration or simulate interpolation with
`$VARIABLE`: Zed treats such values literally in settings fields. Prefer OAuth
or a process-backed integration that reads inherited environment. Zed formats
JSON and JSONC on save with its managed Prettier; `.prettierrc.json` applies
Zed's [documented JSONC parser workaround](https://zed.dev/docs/languages/json#jsonc-prettier-formatting)
to prevent trailing commas. Keep keys, kubeconfigs, auth receipts, and
account-specific state outside this repository.

### Coding agents

One instruction file, `agents/instructions.md`, is every coding agent's global
`AGENTS.md`: the `agents` installer links it as `~/.claude/CLAUDE.md`,
`~/.codex/AGENTS.md`, `~/.agents/AGENTS.md` for Kimi Code, and
`~/.config/opencode/AGENTS.md`. A project's own instructions still take
precedence.

- **Claude Code** runs from Mise; the `claude` cask is the desktop app, which
  includes Claude Code on the desktop. `claude/settings.json` is linked, so a
  change made through `/model` or `/config` shows up as a diff to keep or
  discard. `~/.claude.json` and the rest of `~/.claude` stay machine-local.
- **Codex** runs from Mise. Its `config.toml` records project trust, plugin
  state and desktop preferences, so it is not versioned; `codex/completion.zsh`
  caches the shell completion Codex generates.
- **Kimi Code** runs from Mise. Only `tui.toml` is linked, because
  `config.toml` holds provider credentials and every login rewrites it.
- **Conductor** links `~/.conductor/settings.toml`, the user layer its Settings
  window writes. This repository's own `.conductor/settings.toml` adds a run
  script for `_scripts/test`; Conductor reads it from the default branch on the
  remote, so a change to it applies once merged. The Git message workaround is
  owned by `zsh/zshenv.symlink` (see [Zsh loading order](#zsh-loading-order)).
  When replacing an existing local `~/.zshenv`, use the linker's backup option
  and preserve any unrelated settings. Fully quit and reopen Conductor after
  applying the change to refresh its
  [captured shell environment](https://www.conductor.build/docs/reference/shells).
- **OpenCode** runs from Mise, and the desktop app comes from the
  `opencode-desktop` cask. `opencode.jsonc` declares the models, the CodeGraph,
  Context7, Exa, grep.app and Argent MCP servers, and three plugins;
  `tui.jsonc` holds the terminal defaults. OpenCode has no Anthropic
  subscription login of its own, so that file pins the Anthropic auth plugin on
  the release line matching the installed OpenCode; see the
  [Anthropic provider notes](opencode/README.md#anthropic-provider). The topic
  stays on OpenCode v1 for the reasons in
  [`opencode/README.md`](opencode/README.md#staying-on-opencode-v1).

CodeGraph indexes are per checkout and nothing builds them automatically: the
shared instructions tell an agent to run `codegraph init` when `.codegraph/` is
missing, and to list `.codegraph/**` among the files a repository copies into
new worktrees.

### Trusted roots

A project's `.envrc`, `.env` and Mise configuration take effect without a
per-project `direnv allow` or `mise trust` when the project lives beneath a
trusted root: this checkout, `$WORKSPACE`, or `~/conductor`. Everywhere else,
direnv and Mise still ask. `_scripts/trusted-roots` is the one declaration of
that list. `direnv/install.sh` renders it into the whitelist of
`~/.config/direnv/direnv.toml`, which also loads `.env` files, and
`mise/mise.zsh` exports it as `MISE_TRUSTED_CONFIG_PATHS`. Moving `WORKSPACE`
in `.localrc` therefore takes effect for direnv on the next `dot` run.

## Validation

The test suites create isolated homes and fake external commands; they do not
apply configuration to the real Mac. Run every safe suite without maintaining
a duplicated filename list:

```bash
_scripts/test
```

`tests/documentation_test.sh` ensures that every public `bin/` command, Zsh
function, alias, Homebrew declaration, Mise tool, and installer helper remains
documented. `tests/zed_settings_test.sh` validates the JSON/JSONC formatter
contract. Run the focused suite first, then the complete suite for
repository-wide work.

Static checks used by this repository include:

```bash
git grep -IlzE '^#!.*(bin/sh|bash)([[:space:]]|$)' -- ':!*.md' ':!.agents/' \
  | xargs -0 shellcheck
git grep -IlzE '^#!.*(bin/sh|bash)([[:space:]]|$)' -- ':!*.md' ':!.agents/' \
  | xargs -0 shfmt -d -i 2 -ci -bn
git ls-files -z -- '*.zsh' | xargs -0 -n1 zsh -n
while IFS= read -r -d '' markdown_path; do
  [ ! -f "$markdown_path" ] || mdformat --check "$markdown_path"
done < <(
  git ls-files -z --cached --others --exclude-standard -- '*.md' ':!.agents/'
)
git diff --check
```

The Mise-managed `mdformat` includes the GFM and frontmatter plugins required
to preserve tables and skill metadata. The checks skip the vendored agent
skills under `.agents/`, which `skills-lock.json` records.

GitHub Actions runs the same checks and `_scripts/test` on macOS for every pull
request and every push to `main`; see `.github/workflows/ci.yml`.

CI installs only its required check tools through Mise with `--locked`, using
the repository's config and lock: ShellCheck, shfmt, Go, Python, uv, and mdformat.
The formatter's GFM and frontmatter plugins have explicit versions in the same
declaration. Actions use full commit SHAs, Mise has an explicit version, and the
runner names macOS 15. GitHub may still update that runner image, and the legacy
Mise lock does not freeze all transitive language-package dependencies.

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
- Keep the declaration literal and on one line; a line the declaration reader
  does not accept stops the catalog, the documentation check and upgrade
  discovery for that file.
- Give the new declaration a trailing comment: it is the catalog description
  the catalog renders, and a declaration without one stops the render.
- Run `_scripts/render-software-catalog` to update the catalog tables.
  Documentation coverage reports a stale table, including a declaration missing
  from it.

Implementation, testing, and delivery rules live in
[`CODING_STANDARDS.md`](CODING_STANDARDS.md). Agent-specific instructions live
in [`AGENTS.md`](AGENTS.md).
