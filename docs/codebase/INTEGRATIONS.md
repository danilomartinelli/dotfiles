# External Integrations

The inventory records checked-in commands and configuration. Provider
availability, credentials, active sessions and installed application behavior
were not inspected. Required/optional below describes the calling code's
failure policy, not an invented service-level agreement.

## 1) Integration Inventory

| System                                | Type                                     | Purpose                                                | Auth model in source                                                                        | Criticality                                                                | Evidence                                                               |
| ------------------------------------- | ---------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Git and GitHub                        | Git transport, `gh` CLI, Actions         | Checkout updates, homelab clone, issue workflow and CI | Git/gh manage authentication; identity generated locally                                    | Checkout refresh advisory; a selected clone failure can stop its installer | `_scripts/setup`, `homelab/install.sh`, `docs/agents/issue-tracker.md` |
| Homebrew and Mac App Store            | Package distribution                     | System binaries, apps, fonts and Xcode                 | Homebrew bootstrap has no token in source; App Store sign-in remains manual                 | Availability and bundle reconciliation critical                            | `homebrew/install.sh`, `homebrew/_bundle.sh`, `Brewfile`, `README.md`  |
| Mise and its backends                 | Runtime/package distribution             | Install pinned runtimes and CLIs                       | No registry credential payload is tracked in the declaration                                | `mise install --locked` failure stops installer                            | `mise/config.toml`, `mise/install.sh`                                  |
| Apple tools and Android SDK tools     | Local vendor CLIs                        | Simulator/SDK readiness and explicit provisioning      | No credential payload supplied by these adapters                                            | Checks warn during setup; provisioning is explicit                         | `_scripts/mobile-setup-ios.sh`, `_scripts/mobile-setup-android.sh`     |
| macOS preferences and Launch Services | Local OS APIs through CLIs               | Defaults, Dock, associations and app checklist         | Current user context; some operations have their own privilege requirements                 | Per-module required/optional policy                                        | `_macos/set-defaults.sh`, `dock/install.sh`, `_scripts/checklist`      |
| OpenCode providers/plugins            | Vendor agent runtime                     | Model selection and Anthropic authentication plugin    | Machine-local OAuth/provider state or environment inputs documented in `.localrc.example`   | Optional to dotfiles setup; required when that provider is used            | `opencode/opencode.jsonc`, `opencode/README.md`                        |
| Context7, Exa and grep.app            | Remote MCP                               | Documentation, web and code search                     | Context7 config references `{env:CONTEXT7_API_KEY}`; Exa/grep.app specify no auth field     | Enabled OpenCode integrations; no setup health check                       | `opencode/opencode.jsonc`                                              |
| CodeGraph and Argent                  | Local stdio MCP                          | Code indexing and device control                       | Local process environment; telemetry disabled in declarations                               | Enabled OpenCode integrations; no setup health check                       | `opencode/opencode.jsonc`, `mise/config.toml`                          |
| Zed MCP and ACP agents                | Editor extensions and agent subprocesses | Browser/search/GitHub context and coding agents        | Empty MCP settings or registry-managed agent entries; OpenCode launched through `mise exec` | Editor features, not setup prerequisites                                   | `zed/settings.json`                                                    |
| direnv                                | Shell/environment integration            | Load project environments beneath trusted roots        | Explicit local trust declaration                                                            | Whitelist rendered during topic installation                               | `_scripts/trusted-roots`, `direnv/install.sh`, `mise/mise.zsh`         |
| SSH, age and SOPS                     | Local credential/encryption tooling      | SSH access and encrypted secret workflows              | Private keys generated only by explicit commands; local SSH hosts preserved                 | Credential creation separate from installation                             | `ssh/install.sh`, `ssh/create-key`, `sops/create-key`                  |
| AWS, Kubernetes, Tailscale and Docker | User-invoked infrastructure CLIs         | Shell aliases, completions and environment defaults    | CLI-owned credentials/contexts; no credentials established here                             | Selected command only                                                      | `aws/`, `kubectl/`, `tailscale/`, `docker/`, `.commonrc`               |
| Hermes and homelab                    | Agent CLI and separate repository        | Agent defaults and access/deployment helpers           | Provider configuration is local; homelab uses local SSH identity                            | Individual installer behavior                                              | `hermes/install.sh`, `homelab/install.sh`, `homelab/aliases.zsh`       |
| Determinate Nix installer             | Explicit remote installation script      | Optional Nix and nixd installation                     | Interactive local privilege confirmation described by command                               | Never called automatically by setup                                        | `bin/nix-install`                                                      |

Declared OpenCode remote MCP addresses are `https://mcp.context7.com/mcp`,
`https://mcp.exa.ai/mcp`, and `https://mcp.grep.app`. They are configuration
values, not a live connectivity claim. Likewise, installing cloud/database CLIs
in `Brewfile` or Mise does not make this repository an application connected to
those services.

The upgrade coordinator additionally queries OSV for direct npm/PyPI package
versions. Reports are advisory and explicitly exclude unsupported ecosystems and
transitive Mise dependencies. No vulnerability check is a CI gate. See
`_scripts/upgrade-software` and the controlled-upgrade ADR.

## 2) Data Stores

| Store                                            | Role                                   | Access layer                             | Key risk                                                  | Evidence                                                |
| ------------------------------------------------ | -------------------------------------- | ---------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------- |
| Checked-in files and Git history                 | Authoritative declarations and scripts | Git and owning generators                | Consumer-written linked settings can change source        | `AGENTS.md`, `_scripts/render-software-catalog`         |
| `$HOME` settings and symlinks                    | Installed configuration                | Shared linker and topic installers       | Conflict handling or wrong target could affect user state | `_scripts/link-config`                                  |
| `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles` | Run-once markers                       | Preamble helpers                         | Lost markers re-arm operations                            | `_scripts/installer-preamble.sh`                        |
| `${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles`       | Generated Codex completion             | Codex completion file                    | Stale if Codex changes without a Mise lock change         | `codex/completion.zsh`                                  |
| Tool-owned agent/auth directories                | Vendor runtime/session state           | Vendor tools; only selected files linked | Accidentally versioning private state                     | `agents/install.sh`, `opencode/install.sh`, `AGENTS.md` |
| Docker JSON logs                                 | Local container-log retention policy   | OrbStack Docker settings                 | Not an application observability pipeline                 | `orbstack/docker.json`                                  |

No repository-owned SQL schema, database access layer, message queue, service
mesh or API gateway is declared in the mapped shell implementation. Installed
infrastructure clients operate on separately configured systems.

## 3) Secrets and Credentials Handling

- `.localrc.example` provides placeholder environment-variable names. Setup
  creates `.localrc` and sets mode `600`; agents must not inspect its contents.
- SSH and SOPS installers repair safe paths/permissions and report missing keys.
  `_scripts/key-provisioning.sh` refuses overwrites, sets private directory
  permissions and leaves generation to explicit commands.
- Git identity, kubeconfigs, account state and provider auth stores remain
  machine-private. Kimi's `config.toml` and Codex's `config.toml` are not tracked
  payloads (`AGENTS.md`).
- Reviewed configuration references placeholders or external state; this was not
  a repository-history secret scan. No live secret values were used for this map.
- Automated credential rotation is absent from the key-creation contract.
  [TODO] Current account-specific rotation and recovery arrangements were not
  inspected.

## 4) Reliability and Failure Behavior

- `_scripts/setup` distinguishes critical and advisory operations. It does not
  provide a shared retry/backoff or circuit-breaker layer.
- `homebrew/_bundle.sh` requires successful tap creation and bundle execution;
  tap-trust failure warns and continues.
- `homebrew/install.sh` uses `curl -fsSL`, checks for the string `Homebrew`, then
  runs the downloaded script. It sets no explicit transfer timeout/retry or
  checksum verification. `bin/nix-install` pipes its HTTPS installer to `sh`.
- OpenCode's Argent MCP declaration sets `timeout: 900000` milliseconds. Other
  MCP entries here do not declare a timeout; their defaults belong to OpenCode.
- Mobile check/install dispatch returns failure for failed targets. Normal
  `xcode` and `android-studio` installers convert missing readiness into an
  actionable warning without downloading runtimes.
- [TODO] Current vendor retries, rate limits and authentication behavior require
  separate live verification.

## 5) Observability for Integrations

Shared shell output reports phase and failure context; fixtures capture stdout,
stderr and command events. There is no repository-owned metrics collector or
distributed tracing configuration in the mapped orchestration.

Zed disables diagnostics/metrics telemetry; OpenCode MCP declarations disable
CodeGraph and Argent telemetry. OrbStack caps JSON log files at `10m` with
`max-file: 3`. These are settings, not verification of running processes.

Failures or state inside vendor tools are not measured by the safe fixture
suite. Live package installation, sign-in, devices and external endpoints remain
outside the validation reported in `TESTING.md`.

## 6) Evidence

- [Setup](../../_scripts/setup), [Homebrew bootstrap](../../homebrew/install.sh),
  [bundle wrapper](../../homebrew/_bundle.sh), [Mise installer](../../mise/install.sh)
- [OpenCode declarations](../../opencode/opencode.jsonc),
  [OpenCode notes](../../opencode/README.md), [Zed settings](../../zed/settings.json)
- [Private-environment example](../../.localrc.example),
  [key guards](../../_scripts/key-provisioning.sh)
- [Trusted roots](../../_scripts/trusted-roots), [OrbStack logs](../../orbstack/docker.json)
- [Homelab installer](../../homelab/install.sh), [Nix command](../../bin/nix-install)
