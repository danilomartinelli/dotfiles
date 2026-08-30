# Dotfiles

Danilo Martinelli's personal macOS environment, declared as source. Applying it
changes the current Mac, so the language below distinguishes what this
repository owns from what the installed tools own.

## Language

### Linking

**Config linker**:
The single owner of what happens when a link target already exists. Topic
installers reach it through `installer_link_config`.
_Avoid_: symlinker, link script

**Conflict policy**:
The named rule an installer selects to declare what should happen to an
existing target. The installer states intent; the linker performs the change.
_Avoid_: strategy, mode, conflict handling

### Declaration

**Catalog**:
The single owner of a list, whether declared as data or computed from the
checkout. Consumers read it; none restates it. One consumer is enough: what
makes a list a catalog is that it exists in exactly one place, not how many
readers it has.
_Avoid_: roster, manifest, registry, inventory

### Ownership

**Tool config directory**:
The directory a tool reads its configuration from, whose location is the tool's
contract rather than this repository's preference. Distinct from the run-once
marker directory, which this repository owns and may therefore place where it
likes.
_Avoid_: config home, XDG config directory

**Managed entry**:
A path inside a tool's configuration directory whose editable content this
repository owns and links from the checkout.
_Avoid_: managed file, owned config

**Profile**:
A managed entry that its tool must generate before this repository replaces it,
so its link is always preceded by a tool command.
_Avoid_: preset, variant, flavor

**Generated target**:
A path a tool recreates on every run, which this repository replaces without
preserving. Disposable by definition, so it is never backed up.
_Avoid_: temporary file, scratch path

**Runtime path**:
A path a tool owns entirely, which this repository never links, backs up, or
removes. Distinct from a generated target: both are written by the tool, but
only a generated target is ours to destroy.
_Avoid_: generated, generated state

### Application

**Prerequisite topic**:
A topic whose installer must run before the topics that depend on state it
creates, so its place in the run order is declared rather than inherited from
its name.
_Avoid_: ordered topic, priority topic, first-run topic

**Run-once step**:
An installer step that rebuilds state a person may have rearranged by hand, so
it applies on the first run only. Every other step is safe to repeat, which is
what makes a daily update run harmless.
_Avoid_: one-time setup, first-run hook, bootstrap step

**Run-once marker**:
The record that a run-once step has been applied, and the only thing standing
between an update run and the destruction of that hand-arranged state. Removing
it, or naming its step in the reset variable, re-arms the step.
_Avoid_: stamp, flag, sentinel, lock

**Optional dependency**:
A tool whose absence makes a topic's remaining work meaningless but not wrong,
so the installer says why and stops successfully. Distinct from a required
dependency, whose absence is an error.
_Avoid_: soft dependency, nice-to-have
