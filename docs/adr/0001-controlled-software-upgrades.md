---
status: accepted
---

# Control software upgrades without maintaining a Homebrew distribution

Daily maintenance offers interactive selection of upgrades for declared
software. Homebrew keeps its rolling-release model, with upgrades of installed
packages controlled by the maintenance flow rather than a custom lockfile,
historical recipes, or an artifact mirror. This keeps maintenance within a
personal repository's scope; it does not promise exact Homebrew versions on a
new Mac. Mise keeps its generated lock as the source of resolved tool versions.

Installing missing Homebrew software can require dependency changes, and
applications can update themselves independently of Homebrew. These limits
stay explicit rather than being described as a frozen installation.

Reconciliation applies versions already committed to the Mise lock, including
changes received by a checkout refresh. New releases require an interactive
selection and a final confirmation. Without a terminal, discovery and advisory
reporting continue but no new release is selected. Homebrew's catalog and
client may refresh before selection.

An approved Mise upgrade may change tracked declarations, regenerate selected
lock entries, and render the software catalog; it never commits or pushes.
Explicit channels are preserved, while exact pins may advance to a new major
when the owner selects that candidate.

CI consumes the same locked validation tools as local checks, including
explicit formatter plugin versions. Actions use commit SHAs and the runner
names a macOS major version. The GitHub-hosted image may still receive updates;
maintaining an immutable runner image is outside this scope.

Vulnerability reports belong to CLI maintenance and are advisory. Findings,
unavailable checks, and packages outside scanner coverage are distinguishable.
They do not introduce a CI security gate or prevent an owner-selected upgrade.

## Source publication

An approved Mise upgrade is prepared in staged copies of `mise/config.toml`,
`mise/mise.lock` and `README.md`, and published only after the selected
installs succeed. Before the first write, publication checks that those files
and `Brewfile` still match their snapshots; a concurrent edit aborts it and the
owner's edit is preserved. `Brewfile` is protected but never published:
rendering consumes it, so accepting its modification could publish a catalog
based on obsolete declarations.

Publication is not atomic across files. The original bytes are saved in a
separate recovery area before the first write, because preparation has already
changed the staged copies. If a write fails, restoration attempts every
already-published file even when an earlier restoration fails, and reports the
original error, every restoration failure and the paths left unrestored.
Complete restoration removes the recovery copies; incomplete restoration keeps
them and reports where they are. There is no recovery after process
termination, no coordination between concurrent writers, and no rollback of
installed software or later installer effects.

Staging knows nothing about Mise, lock formats or upgrade candidates; the Mise
manager keeps selected-version and unselected-entry validation. Command
execution, OSV queries and terminal interaction are separate adapters rather
than one general operating-system interface, so orchestration is tested with
in-memory adapters and one subprocess smoke case covers the production wiring.
Mise itself is reached through the policy owner of
[ADR-0006](0006-own-mise-policy-without-changing-project-behavior.md).

Homebrew's [version policy](https://docs.brew.sh/Brew-Bundle-and-Brewfile#versions)
and GitHub's [runner image lifecycle](https://github.com/actions/runner-images#image-definitions)
define the upstream limits behind this decision.
