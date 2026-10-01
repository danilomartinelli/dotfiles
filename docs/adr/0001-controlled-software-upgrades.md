---
status: accepted
---

# Control software upgrades without maintaining a Homebrew distribution

Daily maintenance will offer interactive selection of upgrades for declared
software. Homebrew will retain its rolling-release model, with upgrades of
installed packages controlled by the maintenance flow rather than a custom
lockfile, historical recipes, or an artifact mirror. This keeps maintenance
within a personal repository's scope; it does not promise exact Homebrew
versions on a new Mac.

Installing missing Homebrew software can require dependency changes, and
applications can update themselves independently of Homebrew. These limits
must remain explicit rather than being described as a frozen installation.
Mise retains its generated lock as the source of resolved tool versions.

Reconciliation applies versions already committed to that lock, including
changes received by a checkout refresh. New releases require an interactive
selection and a final confirmation. Without a terminal, discovery and advisory
reporting continue but no new release is selected. Homebrew's catalog and
client may refresh before selection.

An approved Mise upgrade may change tracked declarations, regenerate selected
lock entries, and render the software catalog; it never commits or pushes.
Explicit channels are preserved, while exact pins may advance to a new major
when the owner selects that candidate. Prepare these changes separately and
check unselected entries and concurrent source edits before publishing them.

CI will consume the same locked validation tools as local checks, including
explicit formatter plugin versions. Actions will use commit SHAs and the
runner will name a macOS major version. The GitHub-hosted image may still
receive updates; maintaining an immutable runner image is outside this scope.

Vulnerability reports belong to CLI maintenance and are advisory. Findings,
unavailable checks, and packages outside scanner coverage must be distinguishable.
They do not introduce a CI security gate or prevent an owner-selected upgrade.

Homebrew's [version policy](https://docs.brew.sh/Brew-Bundle-and-Brewfile#versions)
and GitHub's [runner image lifecycle](https://github.com/actions/runner-images#image-definitions)
define the upstream limits behind this decision.
