# danilomartinelli's dotfiles

Personal macOS setup for JavaScript/TypeScript, mobile development, DevOps, and
infrastructure work. The repository installs applications and runtimes, links
configuration into the home directory, and exposes the commands documented
below in every interactive Zsh session.

## First installation

Prerequisites: macOS, Git, and the Xcode Command Line Tools.

```bash
xcode-select --install
git clone https://github.com/danilomartinelli/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
_scripts/bootstrap
```

Bootstrap performs the complete first-run workflow:

1. Creates the private `.localrc` from `.localrc.example` and restricts it to
   mode `600`.
2. Prompts for the Git author name and email and generates the private
   `git/gitconfig.local.symlink`.
3. Links `.localrc` and every public `*.symlink` file into the home directory,
   including the `~/.dotfiles-root` checkout resolver.
4. Applies the tracked macOS defaults and attempts hostname normalization.
5. Installs Homebrew, every dependency in `Brewfile`, and every top-level topic
   installer.

Existing destination files are never silently replaced: bootstrap offers to
skip, overwrite, or back them up. Git identity prompts only appear when the
private Git config does not exist yet.

After bootstrap, open a new shell or run:

```bash
source ~/.zshrc
```

SSH and SOPS setup are non-interactive and never invent credentials during
install. Create keys explicitly when you need them:

```bash
ssh-key-create default
ssh-key-create personal
ssh-key-create work
ssh-key-create work --rsa

sops-key-create default
sops-key-create personal
sops-key-create work
```

## Future updates

Use the public `dot` command for normal maintenance:

```bash
dot
```

It repairs the checkout-root link, attempts `git pull`, ensures Homebrew is
available, runs `brew update`, `brew upgrade`, and `brew bundle`, then reruns
all topic installers. Checkout refresh and Homebrew update/upgrade are advisory;
declared dependency and installer failures stop the run. Unlike bootstrap,
`dot` does not recreate links, prompt for Git identity, or reapply macOS
defaults.

Other lifecycle commands:

| Command | Purpose |
| --- | --- |
| `dot --edit` | Open the active checkout in `$EDITOR` |
| `dot --help` | Show supported options |
| `_scripts/bootstrap` | Run the complete first-machine installation |
| `_scripts/setup bootstrap` | Canonical bootstrap implementation |
| `_scripts/setup update` | Canonical daily-update implementation |
| `dotfiles-root.symlink --install` | Repair `~/.dotfiles-root` for this checkout |
| `set-defaults` | Explicitly reapply tracked macOS preferences |

## What gets installed

`Brewfile` is the source of truth for machine packages and applications. Setup
enables the `xo/xo` and `nikitabobko/tap` taps (and trusts the latter) before
reconciling the file; `xo/xo` supplies the declared `archiver` formula.

### Homebrew formulae

| Formula | Purpose |
| --- | --- |
| `age` | Age encryption used as the SOPS identity backend |
| `aider` | AI pair programming in the terminal |
| `archiver` | Archive support used alongside the Archiver app |
| `awscli` | AWS command-line interface |
| `bat` | `cat` with syntax highlighting |
| `cocoapods` | CocoaPods for React Native / iOS native deps |
| `coreutils` | GNU utilities, including `gls` and `gdate` |
| `direnv` | Per-directory environment variables |
| `dockutil` | Programmatic Dock configuration |
| `duti` | Default application associations |
| `eza` | Modern `ls` replacement |
| `fd` | Modern `find` replacement |
| `fzf` | Fuzzy finder for history, files, and directories |
| `gh` | GitHub CLI |
| `git` | Git |
| `git-lfs` | Git Large File Storage |
| `glab` | GitLab CLI |
| `helm` | Kubernetes package manager |
| `helmfile` | Declarative Helm releases |
| `imagemagick` | Image conversion and manipulation |
| `jq` | JSON processing |
| `kubernetes-cli` | `kubectl` |
| `kustomize` | Kubernetes manifest customization |
| `mas` | Mac App Store CLI |
| `mise` | Runtime manager |
| `neovim` | Terminal editor |
| `opencode` | OpenCode CLI agent |
| `pandoc` | Document conversion |
| `ripgrep` | Fast recursive search |
| `sops` | Encrypt and decrypt secrets (age, KMS, PGP) |
| `spaceman-diff` | Visual image diffs |
| `tmux` | Terminal multiplexer |
| `usage` | Usage-spec CLI support, including Mise completion |
| `watch` | Repeat a command and watch the output |
| `watchman` | Filesystem watcher |
| `wget` | File downloader |
| `wrangler` | Cloudflare Workers CLI |
| `zoxide` | Smarter `cd` |
| `zsh-autosuggestions` | Zsh autosuggestions |
| `zsh-syntax-highlighting` | Zsh syntax highlighting |

### Applications and fonts

| Group | Homebrew casks |
| --- | --- |
| Development | `android-studio`, `lens`, `onlook`, `opencode-desktop`, `orbstack`, `postman`, `tableplus`, `zed` |
| Terminal | `ghostty`, `session-manager-plugin` |
| Window and menu bar | `nikitabobko/tap/aerospace`, `bartender`, `keyclu` |
| Browsers and productivity | `caffeine`, `google-chrome`, `obsidian`, `paste`, `raycast`, `readdle-spark` |
| Design and media | `cleanshot`, `figma`, `spotify` |
| Network and security | `bitwarden`, `tailscale-app`, `whatsapp`, `yubico-authenticator` |
| Fonts | `font-jetbrains-mono-nerd-font` |

The Brewfile also declares the `nikitabobko/tap` tap (trusted during setup) for
AeroSpace. The Mac App Store entry is `Xcode` (app id `497799835`). Archiver
itself must already be installed from the Mac App Store; `archiver/install.sh`
only assigns its supported file associations when the app is present.

Topic installers link or apply machine config for Ghostty, Zed (settings +
default text/source associations via `duti`), AeroSpace, OrbStack Docker engine
defaults, Bartender, KeyClu, Raycast script commands, Tailscale, OpenCode
(`~/.config/opencode`), SOPS age directories, Workspace (`~/Workspace/github.com/<user>`),
Mise, SSH, Archiver, and the Dock.

`tmux/tmux.conf.symlink` provides the multiplexer configuration. Global Aider
defaults live in `aider/aider.conf.yml.symlink` (`~/.aider.conf.yml`) and assume
Ghostty’s dark Catppuccin theme (`dark-mode`, pretty output, monokai code theme).

### Mise runtimes

`mise/mise.toml.symlink` installs the following exact declarations:

| Tool | Version |
| --- | --- |
| `bun` | `1.3.2` |
| `elixir` | `1.18` |
| `erlang` | `27` |
| `go` | `1.25.5` |
| `go:mvdan.cc/sh/v3/cmd/shfmt` | `latest` |
| `java` | `temurin-21` |
| `node` | `lts` |
| `npm` | `11.6.3` |
| `npm:eas-cli` | `16.28.0` |
| `pipx:mdformat` | `latest` |
| `pnpm` | `10.23.0` |
| `python` | `3.14.0` |
| `ruby` | `3.4` |
| `rust` | `1.91.1` |
| `terraform` | `1.14.0` |
| `uv` | `latest` |
| `yarn` | `4.11.0` |

Run `mise install` to reconcile only these runtimes. `pipx:mdformat` formats
Markdown; `shfmt` is installed through the Go backend on top of the managed Go
toolchain.

## Public commands

`bin/` is a public command directory, not an internal implementation detail.
Zsh adds it to `PATH`. A file named `git-foo` can be invoked as either
`git-foo` or the preferred Git subcommand form `git foo`.

### General utilities

| Command | Usage and purpose |
| --- | --- |
| `battery-status` | Print the macOS battery indicator used by the prompt |
| `dns-flush` | Flush the macOS DNS cache with `sudo` |
| `dot` | Run daily dotfiles maintenance or open the checkout |
| `e` | `e [path]`: open a path, or the current directory, in `$EDITOR` |
| `headers` | `headers URL`: print HTTP response headers using `curl` |
| `set-defaults` | Apply `_macos/set-defaults.sh` from the active checkout |
| `sops-key-create` | `sops-key-create <role>`: create a non-overwriting age identity for `default`, `personal`, or `work` |
| `ssh-key-create` | `ssh-key-create <role> [--rsa]`: create a non-overwriting SSH key for `default`, `personal`, or `work` |

### Git utilities

| Executable | Preferred invocation and purpose |
| --- | --- |
| `git-all` | `git all`: stage all changes |
| `git-amend` | `git amend`: amend with the existing commit message |
| `git-copy-branch-name` | `git copy-branch-name`: copy the current branch name to the macOS clipboard |
| `git-credit` | `git credit "Name" email`: amend the last commit with another author |
| `git-delete-local-merged` | `git delete-local-merged`: delete branches merged into `HEAD`, preserving current, `main`, and `master` |
| `git-edit-new` | `git edit-new`: open untracked files in `$EDITOR` |
| `git-nuke` | `git nuke branch`: force-delete a local branch and delete the matching `origin` branch |
| `git-promote` | `git promote`: push the current branch and configure `origin` tracking |
| `git-rank-contributors` | `git rank-contributors [-v] [-o] [-h]`: rank authors by changed lines |
| `git-track` | `git track`: track the matching existing branch on `origin` |
| `git-undo` | `git undo`: soft-reset the latest commit while preserving changes |
| `git-unpushed` | `git unpushed`: diff local commits not yet on the matching `origin` branch |
| `git-unpushed-stat` | `git unpushed-stat`: summarize the unpushed diff and commit count |
| `git-up` | `git up [pull options]`: pull and list newly received commits |
| `git-wtf` | `git wtf [options]`: summarize local/remote branch relationships |

`git nuke` changes both local and remote state. `git credit`, `git amend`, and
`git undo` rewrite local commit state; inspect their help/comments before use.

## Zsh functions and aliases

`functions/` is added to `fpath` and autoloaded. Files without a leading `_`
are public functions; leading-underscore files are completion implementations.
The current public functions are:

| Function | Usage and purpose |
| --- | --- |
| `c` | `c [project]`: change to `$PROJECTS/project` (`$PROJECTS` defaults to `~/Workspace/github.com`) |
| `extract` | `extract archive`: extract supported tar, gzip, bzip2, zip, pax, rar, or `.Z` files; mount `.dmg` on macOS |
| `gf` | `gf remote-branch`: create a local branch tracking `origin/remote-branch` |
| `pubkey` | Copy the default Ed25519 public key, falling back to RSA |

The shell also exposes these aliases. Arguments written after an alias are
passed to the expanded command.

| Area | Aliases |
| --- | --- |
| Shell | `reload!` → source `~/.zshrc`; `cls` → clear; `grep` → colored output |
| Files | `ls`, `l`, `ll`, `la`, `lt` → `eza` (falls back to GNU `gls`); `cat` → `bat` |
| Editor | `v`, `vi` → Neovim; `vimrc` → edit `~/.vimrc` |
| Homebrew | `bi`, `bu`, `bug`, `bs`, `binfo`, `brews`, `brewsc` |
| Mise | `m`, `mi`, `mu`, `ml`, `mc` |
| Aider | `aider-architect`, `aider-ro` |
| Docker | `d` → Docker; `dc` → Docker Compose |
| Mobile | `android`, `android_devices`, `ios`, `ios_devices`, `rn`, `rni`, `rna`, `pods` |
| Tailscale | `ts`, `tsstatus`, `tsip`, `tsup`, `tsdown`, `tsping` |
| SOPS | `sops-encrypt`, `sops-decrypt`, `sops-edit` |
| SSH | `sshclean` → remove sockets and stop SSH processes |
| Git | `gl`, `glog`, `gp`, `gd`, `gc`, `gca`, `gco`, `gcb`, `gb`, `gs`, `gac`, `ge` |
| Kubectl context | `k`, `kk`, `kctx`, `kctx-list`, `kcurrent`, `konfig`, `kctx-witek`, `kns` |
| Kubectl resources | `kgp`, `kgpa`, `kgs`, `kgsa`, `kgd`, `kgda`, `kgn`, `kgns` |
| Kubectl operations | `kdp`, `kds`, `kdd`, `kdn`, `kl`, `klf`, `klt`, `kaf`, `kdf`, `kex`, `kpf`, `kwp`, `kwpa` |
| AWS basics/output | `awsl`, `awswho`, `awsregion`, `awsjson`, `awstable`, `awstext`, `awscost` |
| AWS S3 | `s3ls`, `s3cp`, `s3mv`, `s3rm`, `s3sync`, `s3mb`, `s3rb`, `s3web` |
| AWS EC2 | `ec2ls`, `ec2start`, `ec2stop`, `ec2reboot`, `ec2terminate`, `ec2ip` |
| AWS Lambda/CloudFormation | `lambdals`, `lambdainvoke`, `lambdalogs`, `lambdadeploy`, `cfnls`, `cfnvalidate`, `cfnevents`, `cfnoutputs` |
| AWS ECS/RDS | `ecsls`, `ecsservices`, `ecstasks`, `ecsdescribe`, `rdsls`, `rdsstart`, `rdsstop` |
| AWS IAM/SSM | `iamusers`, `iamroles`, `iamgroups`, `iampolicies`, `ssmls`, `ssmget`, `ssmput`, `ssmsession` |
| AWS CloudWatch/DynamoDB | `cwlogs`, `cwtail`, `cwalarms`, `dynamols`, `dynamoscan`, `dynamoquery` |

## Repository architecture

```text
dotfiles/
├── bin/                    # Public executables added to PATH
├── functions/              # Public autoload functions and _ completions
├── tests/                  # Repository tests; intentionally visible to tooling
├── _scripts/               # Private setup adapters and orchestration
├── _macos/                 # Private macOS configuration implementation
├── topic/                  # Tool-specific shell files and optional installer
├── Brewfile                # Homebrew source of truth
├── dotfiles-root.symlink   # Worktree-aware checkout resolver
└── .localrc.example        # Private environment template
```

Topic directories may contain:

```text
topic/
├── install.sh       # Optional installer run by bootstrap and dot
├── *.symlink        # Linked into the home directory during bootstrap
├── path.zsh         # Loaded first
├── aliases.zsh      # Loaded with main topic configuration
├── env.zsh          # Loaded with main topic configuration
├── completion.zsh   # Loaded after compinit
└── *.zsh            # Other visible topic configuration
```

Top-level directories and nested files whose names begin with `_` are reserved
and excluded from topic discovery. That convention is why implementation lives
in `_scripts/` and `_macos/`. The visible roots `bin/`, `functions/`, and
`tests/` are explicit non-topics: they are never classified as shell topics.
`tests/` deliberately does not use an underscore: tests are neither shell
topics nor private startup implementation, and the conventional name keeps
them discoverable by humans and tooling.

`_scripts/topic-catalog <repository-root>` is the single private interface
that classifies this layout for setup, Zsh startup, and the documentation
test. It emits deterministic, tab-separated `kind<TAB>absolute-path` records
sorted by kind and path, with kinds `topic`, `link`, `installer`, `path`,
`main`, `prompt`, `completion`, and `aliases`. An `aliases.zsh` file emits
both `main` and `aliases` records; only `zsh/prompt.zsh` is the authoritative
`prompt`; `homebrew/install.sh` is excluded from `installer` records because
Homebrew has its own setup phase.

### Zsh loading order

`zsh/zshrc.symlink` resolves the checkout and sources `zsh/_startup.zsh` once.
The startup module then:

1. Loads `~/.localrc` followed by tracked `.commonrc`.
2. Initializes Homebrew, `PATH`, `MANPATH`, function paths, and topic discovery.
3. Sources sorted topic `path.zsh` files, then other visible `*.zsh` files.
4. Loads the custom prompt as the sole prompt implementation.
5. Runs `compinit` once and loads sorted `completion.zsh` files.
6. Loads optional Zsh syntax highlighting last.

Reloading remains idempotent: loader paths and hooks are de-duplicated.

### Secrets and machine-local files

Store secrets in the gitignored `.localrc`, which bootstrap links to
`~/.localrc`. Store shared non-secret defaults in tracked `.commonrc`. Never
commit the generated `git/gitconfig.local.symlink`. Keep private SSH hosts in
`~/.ssh/config_local`; the tracked SSH config includes it and provisioning does
not overwrite it.

Age private keys for SOPS live in `~/.config/sops/age/` (mode `600`) and are
never committed. `sops/env.zsh` exports `SOPS_AGE_KEY_FILE` and, when present,
`SOPS_AGE_RECIPIENTS` from `recipient.txt`.

`.localrc.example` includes commented templates for Git identity exports and
OpenCode provider keys (`MOONSHOT_API_KEY` / Kimi, `MINIMAX_API_KEY`,
`ZHIPU_API_KEY` / GLM / Z.AI, `OPENCODE_API_KEY` for Zen/Go). OpenCode reads
those environment variables automatically once they are exported from
`~/.localrc`; the linked `~/.config/opencode/` tree also ships base skills.

`.context/` is local Conductor/agent workspace state and is intentionally
gitignored. It is not project configuration.

## Validation

All tests use temporary homes or fixtures and do not change the real machine:

```bash
tests/setup_test.sh
tests/zsh_startup_test.sh
tests/ssh_provisioning_test.sh
tests/sops_provisioning_test.sh
tests/git_branch_state_test.sh
tests/homebrew_availability_test.sh
tests/documentation_test.sh
tests/topic_catalog_test.sh
_scripts/test-checkout-root
```

The behavioral suites source `tests/_support/shell-scenario.sh` for temporary
fixture cleanup, fake executable creation, output and event capture, shared
assertions, and TAP reporting. Domain-specific fake behavior stays in the suite
that owns it.

`tests/documentation_test.sh` guards README coverage for every `bin/` command,
shell alias, public function, Brewfile package, and Mise tool declaration.

`homebrew/_availability.sh` is the private interface used by installation,
setup, and Zsh startup to resolve the same Homebrew executable and prefix rules.

After changing shell configuration, run the relevant tests and then `reload!`.

## Adding a topic or dependency

Create a non-reserved top-level topic, follow the filenames above, make any
`install.sh` executable, and run it directly or use `dot`. Add Homebrew items to
`Brewfile`; add runtimes to `mise/mise.toml.symlink`. Update this README in the
same change—the documentation test will report uncovered public names.
