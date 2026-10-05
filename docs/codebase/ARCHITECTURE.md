# Architecture

## 1) Architectural Style

The repository combines tool-specific topics, thin public command adapters,
shared shell modules and declarative catalogs. `_scripts/topic-catalog` is the
common discovery mechanism used by setup, shell startup and documentation
checks. There are no application controller/service/database layers.

Three constraints shape the implementation:

- Applying configuration mutates the host; validation uses isolated fixtures.
- The physical checkout must remain correct when invoked through symlinks or
  from a linked Git worktree.
- Private credentials and tool-owned runtime state must stay outside tracked
  configuration, while repeated installation must preserve user-owned state.

See `AGENTS.md`, ADR-0004, and `_scripts/link-config`.

## 2) System Flow

```text
bin/dot (resolves the checkout containing it)
  -> _scripts/setup update
      -> advisory git pull -> private template -> safe links
      -> Homebrew availability -> advisory maintenance/update
      -> Brewfile reconciliation -> prerequisite topics -> remaining topics
          -> installer-preamble.sh -> catalogs/link-config/vendor commands
      -> upgrade-software -> advisory audit -> interactive selection/confirmation
  -> phase output and exit status
```

1. `bin/dot` selects edit or update and obtains `DOTFILES_ROOT` through the
   adapter resolver.
1. `_scripts/setup` repairs the resolver link, tries checkout refresh, creates a
   missing private environment template and links with `--batch skip`.
1. Homebrew availability and declared dependencies are critical. Legacy cleanup,
   `brew update`, interactive upgrades, and checkout refresh are advisory.
   Bundle reconciliation uses `--no-upgrade`; new releases need selection.
1. Discovery supplies installer paths. `workspace` runs first because subsequent
   topics consume the layout it creates; remaining installers follow catalog order.
1. Each installer sources the preamble, checks its dependencies, and applies its
   own settings through shared helpers. Mise installs with `--locked`.
1. Critical failures stop setup; optional operations report why they skipped.
   Success means the executed operations completed, not that manual sign-ins or
   all optional integrations are ready.

Bootstrap instead creates private Git identity when absent, links files,
applies macOS defaults, and enters the dependency pipeline. Daily update does
not reapply those defaults. These orders come from `_scripts/setup`.

Shell startup is a separate flow:

```text
zshenv.symlink -> person's shell or tool shell, and its locale
zshrc.symlink -> physical checkout -> .localrc -> .commonrc
  -> Homebrew and unique paths -> topic catalog -> autoload functions
  -> topic paths -> topic main files -> sole prompt -> compinit
  -> completions -> optional autosuggestions -> optional syntax highlighting
```

`zsh/_startup.zsh` runs the classifier on every pass, without a cache, and
cleans its private loader variables after each pass. The classifier starts one
`find` and one `sort` whatever the topic count, which `tests/topic_catalog_test.sh`
enforces. `tests/zsh_startup_test.sh` covers nested additions and removals
reaching the next shell.

## 3) Layer/Module Responsibilities

| Layer or module                | Owns                                                                                         | Must not own                                   | Evidence                                                                            |
| ------------------------------ | -------------------------------------------------------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------- |
| `_scripts/setup`               | Phase ordering, prerequisite ordering and failure severity                                   | App lists or per-tool link behavior            | `_scripts/setup`, `_scripts/checklist`                                              |
| `_scripts/topic-catalog`       | Deterministic kind/path classification                                                       | Applying discovered configuration              | `_scripts/topic-catalog`                                                            |
| `installer-preamble.sh`        | Installer context, guards, run-once markers and linking wrappers                             | Creating credentials                           | `_scripts/installer-preamble.sh`                                                    |
| `link-dotfiles`, `link-config` | Conflict selection and target classification/mutation respectively                           | Package-manager orchestration                  | Both linker sources                                                                 |
| Catalog/rendering modules      | TSV reading, explicit placeholder expansion, generated-region validation and file comparison | Consumer-specific catalog meaning              | `_scripts/catalog.sh`, `_scripts/generated-region.sh`, `_scripts/generated-file.sh` |
| Mobile target adapters         | iOS/Android observations and explicit installation                                           | Implicit runtime downloads during normal setup | `_scripts/mobile-setup`, `xcode/install.sh`, `android-studio/install.sh`            |
| Key-creation commands          | Explicit generation with shared refusal/permission guards                                    | Generation during topic installation           | `ssh/create-key`, `sops/create-key`, `_scripts/key-provisioning.sh`                 |

## 4) Reused Patterns

| Pattern                                   | Where found                                         | Why it exists                                                                      |
| ----------------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Public adapter delegates to private owner | `bin/dot`, `bin/mobile-setup`                       | Stable user commands with one implementation owner                                 |
| Catalog plus handler                      | `catalog_each_row`, defaults, Dock, associations    | Preserves ordering, handles final lines and keeps child commands off catalog input |
| Explicit conflict policy                  | `_scripts/link-config`                              | Chooses preservation, backup or confirmed replacement without hiding outcomes      |
| Run-once marker                           | `_scripts/installer-preamble.sh`, `dock/install.sh` | Preserves manually rearranged state unless `DOTFILES_RESET` re-arms it             |
| Staged generated output                   | `_scripts/render-software-catalog`                  | Validates all regions before replacing the documented file                         |
| Command stubs and injected paths          | `tests/_support/fixture.sh`, `tests/setup_test.sh`  | Exercises process/filesystem boundaries without applying to the real host          |

`catalog_each_row` passes seven arguments on file descriptor 3 and uses shared
shell variables. It explicitly forbids nested calls. Catalog stdout from
`topic-catalog` is the documented exception to the catalog-file reader rule.

## 5) Known Architectural Risks

- **Discovery cost is startup cost:** every interactive shell runs the
  classifier. Keep it at one `find` and one `sort` rather than adding a cache,
  whose freshness rule would have to agree with the classifier; see
  `CONCERNS.md`.
- **Shared helpers have broad reach:** a change to linking, preamble, catalogs,
  or setup affects many topics. Their fixture suites and the complete test runner
  are the validation boundary prescribed by `CODING_STANDARDS.md`.
- **Tracked settings are writable by their consumers:** Zed and several coding
  agents can change a linked file, producing a real source diff. Inspect it
  rather than automatically discarding it (`AGENTS.md`).
- **External program semantics remain external:** package installation, app
  authentication and device operation are exercised through controlled stubs,
  not proved by repository tests (`tests/_support/stubs.sh`).

No repository-owned queue, event bus or background worker was found in the
tracked implementation. Locally launched MCP servers and installed vendor
daemons are integrations, not an internal event architecture.

## 6) Evidence

- [Update adapter](../../bin/dot), [setup](../../_scripts/setup)
- [Checkout resolution decision](../adr/0004-each-entry-point-resolves-its-own-checkout.md), [topic classifier](../../_scripts/topic-catalog)
- [Preamble](../../_scripts/installer-preamble.sh), [linker](../../_scripts/link-config)
- [Catalog reader](../../_scripts/catalog.sh), [renderer](../../_scripts/render-software-catalog)
- [Shell startup](../../zsh/_startup.zsh), [setup fixtures](../../tests/setup_test.sh)
