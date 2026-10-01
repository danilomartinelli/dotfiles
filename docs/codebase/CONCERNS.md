# Codebase Concerns

Findings were discovered at `9acba575` on 2026-10-01. This map now includes
local corrections from the subsequent diagnosis. Historical reproduction
results are labeled separately from the corrected behavior and remaining
operational boundaries.

## 1) Top Risks (Prioritized)

| Severity                         | Concern                                                                                                          | Evidence                                                               | Impact                                                                    | Suggested action                                                                            |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Medium, reproducibility boundary | Homebrew declarations and CI lint installations are not locked to the same resolved versions as local Mise tools | `Brewfile`, `.gitignore`, `.github/workflows/ci.yml`, `mise/mise.lock` | Different installation dates can produce different packages/check results | Use the README's explicit version-policy distinction; record versions when diagnosing drift |

### Resolved: nested Zsh cache invalidation

The catalog recursively finds visible `.zsh` files. Previously, startup checked
only root and immediate topic-directory mtimes before reusing its cache. An
addition inside an existing nested directory changed neither of those mtimes.

The deterministic reproduction warmed a cache in a temporary checkout, then
added `alpha/nested/added.zsh`. A fresh classifier found the file, but a new
shell using the old cache did not load it. Advancing only the nested directory's
mtime did not help; advancing the topic directory's mtime did. This isolated
cache invalidation depth as the cause, rather than timestamp precision or file
classification.

`zsh/_startup.zsh` now checks directory mtimes recursively. The regression at
`tests/zsh_startup_test.sh` exercises the real shell entrypoint with controlled
fixture mtimes and covers nested additions, renames out of and back into the
`.zsh` classification, and removal.

```text
Before: _scripts/test zsh_startup
not ok 4 - nested topic additions, renames and removals refresh cached startup

After: _scripts/test zsh_startup
ok 4 - nested topic additions, renames and removals refresh cached startup
```

The original isolated reproduction also now reports `nested=loaded` after the
addition. Only fixture state was changed during reproduction; the installed
shell and cache were not used to validate it.

### Resolved: stub failure-control drift

The former Mise control used `FAKE_MISE_INSTALL_STATUS`, while duti treated
`FAIL_DUTI` as identifiers rather than a status. Using the documented status
controls therefore returned success. The same naming drift existed in the
Xcode and Android fixture commands.

The shared and mobile fixture stubs now use `FAIL_*` for exit codes. Duti's
optional `FAKE_DUTI_IDENTIFIERS` selector limits a numeric `FAIL_DUTI` to chosen
rows. Consumers were migrated together, including per-run association-test
overrides that no longer export failure injection between invocations.

Existing Mise, Archiver and mobile failure scenarios went red with the
corrected controls before the stubs changed and passed after the change.
`CODING_STANDARDS.md` now explicitly distinguishes status, output and simulated
state, rather than promising every unset stub succeeds silently.

## 2) Technical Debt

| Debt item            | Why it exists                                                                      | Where                                                                                                                                                   | Risk if ignored                                                     | Suggested fix                                                                              |
| -------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Large fixture suites | Suites contain setup and many cases; size alone does not establish a design defect | `tests/installer_preamble_test.sh` (857 lines), `tests/mobile_setup_test.sh` (813), `tests/setup_test.sh` (718), `tests/generated_region_test.sh` (638) | Maintenance requires understanding fixture state and shared helpers | Use the owning shared fixture modules when extending behavior; avoid speculative splitting |

At the initial `9acba575` baseline, a tracked shell-source sweep found **zero `TODO`/`FIXME`/`HACK` markers** in the
170 inspected shell files, including tests. None of the shell implementation
files exceeded 500 lines; the four files above are tests. This is a scoped
inventory result, not evidence that no defects exist. Vendored skills were
excluded. The generic scanner omits shell extensions and `bin/`, so its marker
and line-count results alone are unsuitable for this repository.

## 3) Security Concerns

These are existing trust boundaries, not claims of exploitation or new
vulnerabilities.

| Risk                                               | OWASP category           | Evidence                                                       | Current mitigation                                                             | Gap                                                                                                                          |
| -------------------------------------------------- | ------------------------ | -------------------------------------------------------------- | ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| Remote installer supply-chain trust                | N/A for this shell setup | `homebrew/install.sh`, `bin/nix-install`                       | HTTPS; Homebrew content sanity check; Nix installation is explicit             | No pinned checksum/signature verification implemented by these wrappers                                                      |
| Project configuration executes under trusted roots | N/A                      | `_scripts/trusted-roots`, `direnv/install.sh`, `mise/mise.zsh` | One explicit root declaration shared by both tools                             | Every project placed under a trusted prefix inherits this policy                                                             |
| User-state replacement during installation         | N/A                      | `_scripts/link-config`, `_scripts/key-provisioning.sh`         | Backups/preservation policies, dangerous-target refusal, key-overwrite refusal | These guards do not replace correct caller target selection                                                                  |
| Agent/editor authority is broad by declaration     | N/A                      | `zed/settings.json`                                            | Source is inspectable; secrets remain outside tracked configuration            | `trust_all_worktrees`, broad sandbox permissions and agent modes are permissive settings; live enforcement was not inspected |

No credential files, auth stores, private keys or account state were read.
[TODO] Repository-history secret scanning and live permission/authentication
verification are outside this mapping exercise.

## 4) Performance and Scaling Concerns

| Concern                     | Evidence                                        | Current symptom                                                                            | Scaling risk                                                      | Suggested improvement                                                              |
| --------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Ordered installer execution | `_scripts/setup`                                | No latency measurement collected                                                           | Total setup time includes vendor operations executed sequentially | Preserve declared prerequisites; measure before considering concurrency            |
| Vendor device-call timeouts | `opencode/opencode.jsonc`, `opencode/README.md` | Existing runbook describes Android boot/unlock failures; not reproduced in this inspection | Provider/device latency is outside fixture timing                 | Keep diagnosis at the documented CLI/device boundary; measure the actual operation |

No application database queries, N+1 access patterns or distributed caches are
present in the mapped shell core. No benchmark/profiling configuration was
found in the tracked repository inventory. [TODO] Shell-startup and complete
setup latency have not been benchmarked in this task.

## 5) Fragile/High-Churn Areas

The skill's `git log --since='90 days ago' --name-only --pretty=format:` scan
counted file appearances in history reachable from the inspected HEAD. Churn
identifies review attention, not proof of fragility.

| Area                                             | Why review carefully                                       | Churn signal              | Safe change strategy                                   |
| ------------------------------------------------ | ---------------------------------------------------------- | ------------------------- | ------------------------------------------------------ |
| `README.md`                                      | Public contracts and generated regions coexist             | 95 appearances            | Use the renderer and documentation checks              |
| `AGENTS.md`, `CODING_STANDARDS.md`               | Procedure and normative rules affect all work              | 59 and 41 appearances     | Cross-check current implementation and CI              |
| `opencode/README.md`, `opencode/install.sh`      | Subsystem ownership changed substantially                  | 44 and 30 appearances     | Read current two-file installer and agent fixtures     |
| `mise/mise.lock`, `mise/config.toml`, `Brewfile` | Dependency declarations and resolved state differ          | 35, 22 and 33 appearances | Regenerate the lock through its owner; review narrowly |
| `tests/setup_test.sh`, `_scripts/setup`          | Phase ordering and failure contracts                       | 31 and 22 appearances     | Use the setup fixtures and complete safe runner        |
| `zed/settings.json`                              | Both repository edits and application writes can affect it | 28 appearances            | Preserve unrelated app writes and run config checks    |

The scan also reports removed paths such as `tests/opencode_install_test.sh`
(61 appearances), `opencode/opencode.symlink/opencode.jsonc` (32), and
`opencode/orchestrator/README.md` (22). They are historical paths, not current
modules or tests. Current OpenCode link coverage is in
`tests/agents_install_test.sh`.

### Intent versus reality

- **Discovery:** the nested-file omission was reproduced and corrected. Startup
  now invalidates its cache for nested additions, renames and removals.
- **Fixture convention:** failure controls and their consumers now agree on
  numeric `FAIL_*` values, with output/state supplied separately.
- **Reproducibility:** the README now describes the actual declarative setup:
  Mise installations are locked, while Homebrew and CI tooling remain floating.
  No package-version policy was changed as part of this diagnosis.
- **Scanner expectations:** the generic upstream scanner does not recognize
  `Brewfile`, Mise or the shell entrypoints. The map supplements it with tracked
  source inventory; the vendored scanner was not changed.

## 6) `[ASK USER]` Questions

No unresolved intent-dependent question is needed to complete this source map.
The sole owner, operating platform, documentation ownership and publication
boundary are explicit in `AGENTS.md`. The confirmed code and fixture defects
were corrected locally; remaining trust and version policies are documented
operational boundaries.

## 7) Evidence

- [Startup/cache](../../zsh/_startup.zsh), [classifier](../../_scripts/topic-catalog),
  [startup fixtures](../../tests/zsh_startup_test.sh)
- [Stub implementation](../../tests/_support/stubs.sh),
  [normative conventions](../../CODING_STANDARDS.md)
- [Dependencies](../../Brewfile), [lock](../../mise/mise.lock),
  [CI](../../.github/workflows/ci.yml), [ignore rules](../../.gitignore)
- [Installer download](../../homebrew/install.sh),
  [linker guards](../../_scripts/link-config), [key guards](../../_scripts/key-provisioning.sh)
- [Trusted roots](../../_scripts/trusted-roots), [editor settings](../../zed/settings.json)
- Terminal evidence: tracked inventory and shell line/marker sweep at `9acba575`;
  the 90-day history scan and the before/after diagnosis recorded above. Fixture
  line counts in the debt table refer to that initial baseline.
