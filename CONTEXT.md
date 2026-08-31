# Dotfiles

Danilo Martinelli's personal macOS environment, declared as source. Applying it
changes the current Mac, so the language below distinguishes what this
repository owns from what the installed tools own.

## Language

### Linking

**Config linker**:
The single owner of what happens when a link target already exists, and the
only place a link target is removed or backed up. Topic installers reach it
through `installer_link_config`; home linking reaches it directly.
_Avoid_: symlinker, link script

**Target classification**:
What an existing link target is, before any policy applies: current, a
conflict, or absent. The config linker has to answer this to act at all, so it
answers it for callers too rather than letting each one re-derive it by its own
path arithmetic. Distinct from a conflict policy, which is what a caller wants
done about a conflict rather than what the conflict is.
_Avoid_: link state, target check, already-linked

**Conflict policy**:
The named rule a caller selects to declare what should happen to an existing
target. The caller states intent; the linker performs the change, or fails
because it cannot perform it. A policy that keeps the target is honoured, not
refused.
_Avoid_: strategy, mode, conflict handling

**Confirmed replacement**:
The intent a caller states when a person, not a classification, decided a
target should go: an answer at a prompt or an explicit batch instruction.
Destroys like a generated-target replacement and shares its refusals,
because what a removal must never touch does not depend on why it was asked
for. Distinct from a generated target, which is a claim about who writes the
file rather than about who chose.
_Avoid_: force, overwrite, user-approved

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

### Credentials

**Key provisioning**:
The creation of new key material, which only an explicit command performs. A
topic installer may repair the directories and modes around existing keys and
report that one is missing; it never generates one.
_Avoid_: key generation, credential setup, key bootstrap

**Key role**:
The name a person selects to say which of a tool's keys they mean — `default`,
`personal`, or `work` — and the only input that decides where the material
lands. Distinct from the key type, which is how the key is generated rather
than which key it is.
_Avoid_: profile, identity name, key slot

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

**File-type association**:
A request that macOS route one file-type identifier — a filename extension or a
UTI — to a topic's app in a named role. A topic declares the whole set it
claims; it does not describe how each one is applied.
_Avoid_: file type binding, default app mapping, UTI claim, handler

**Best-effort association**:
An association whose failure is expected rather than reported, because Launch
Services does not recognise every identifier on every macOS version. Every
other association's failure is named and counted.
_Avoid_: optional association, soft association, fallback UTI

**Association role**:
The capability an association claims. Never the one that claims everything,
because a role macOS already maps elsewhere — the browser's hold on HTML —
turns applying a default into a system prompt.
_Avoid_: handler role, all, viewer/editor

**Mobile Provisioning**:
The Application that assesses and reconciles a machine’s native iOS and Android
prerequisites.
_Avoid_: mobile setup

**Mobile Readiness**:
The declared assessment of a selected Mobile Target’s required conditions and
permitted next action.
_Avoid_: environment status

**Mobile Target**:
iOS, Android, or both selected for Mobile Provisioning.
_Avoid_: platform selector
