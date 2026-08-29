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
The single owner of a list that more than one consumer needs, whether declared
as data or computed from the checkout. Consumers read it; none restate it.
_Avoid_: roster, manifest, registry, inventory

### Ownership

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
