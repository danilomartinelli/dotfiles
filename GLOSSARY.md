# Personal macOS environment

The software and configuration Danilo declares for his Mac, and the maintenance
that keeps that environment current.

## Language

### Software

**Declared software**:
Software explicitly selected as part of the managed Mac environment. Software
installed independently is outside this set.
_Avoid_: All installed software

**Declaration**:
The owner's explicit selection of one piece of declared software. A source that
software comes from, such as a Homebrew tap, is not a declaration.
_Avoid_: Entry, package line

**Catalog description**:
The owner's short explanation of a declaration, published beside it in the
catalog of declared software.
_Avoid_: Role, purpose

**Pin**:
A declaration that selects one exact release. The owner may move it to any newer
release, including a new major version.
_Avoid_: Fixed version

**Channel**:
A declaration that selects a moving line of releases, such as the latest
release, a long-term-support line, or every release sharing a version prefix.
Upgrades advance within the channel and never change it.
_Avoid_: Floating version, range

**Upgrade candidate**:
A newer available release of declared software that the owner may select for
installation. Availability alone does not authorize a version change.

**Controlled upgrade**:
A change to installed software that follows the owner's explicit selection of
upgrade candidates, including dependencies required by those selections.
_Avoid_: Frozen machine, automatic upgrade

### Shells

**Person's shell**:
A shell whose output a person reads, whichever app opened it.
_Avoid_: Interactive shell, terminal shell

**Tool shell**:
A shell whose output a program reads, such as a coding agent's command shell
or an app's internal shell.
_Avoid_: Agent shell, non-interactive shell, Conductor shell

### Configuration

**Topic**:
A unit of the managed environment that gathers the configuration, shell setup
and optional installation step for one tool or concern.
_Avoid_: Module, package, plugin

**Catalog**:
A tracked table the owner edits by hand, each row naming one piece of
configuration that a single consumer applies in row order. The topic catalog and
the software catalog are computed or rendered, not catalogs in this sense.
_Avoid_: Manifest, list

**Run-once step**:
Configuration applied only on a machine's first apply, because reapplying it
would overwrite arrangements the owner made by hand. A reset re-arms it.
_Avoid_: First-run only, one-shot

### Linking

**Destination**:
The place in the home directory where the environment puts a link to its own
configuration.
_Avoid_: Target

**Conflict**:
Something already at a destination that is not the link the environment
declares there.
_Avoid_: Collision, clash

### Checkouts

**Checkout**:
A copy of this repository on disk from which the environment can be applied. A
Git worktree is a checkout too.
_Avoid_: Clone, dotfiles directory

**Active checkout**:
The checkout whose configuration is in effect on the Mac. A command acts on the
checkout that contains it, which need not be the active checkout.
_Avoid_: Main checkout, physical checkout
