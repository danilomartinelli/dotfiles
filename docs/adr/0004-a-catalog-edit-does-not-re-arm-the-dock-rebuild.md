# A catalog edit does not re-arm the Dock rebuild

The Dock layout is declared data in `dock/_layout.tsv`, but applying it stays
gated by the `dock` run-once marker. Editing a row changes what the next apply
would build; it does not build it. `DOTFILES_RESET=dock dot` does.

## Considered options

Hashing the catalog into the marker was the obvious way to make an edit
self-applying, and it is why this file exists: it is wrong in a way that shows
up exactly once. The rebuild opens with `dockutil --remove all`. A hash that
changes on every catalog edit also changes on every `git pull` that touches a
row, so a routine `dot` would wipe a Dock someone had spent months arranging by
hand. The marker exists to prevent precisely that, and a content hash
reintroduces the destruction through the back door — fired by a remote change
rather than a local one, which is the worse of the two.

Reconciling rather than rebuilding — comparing the declared rows against
`dockutil --list` and touching only the difference — would make the step
idempotent and retire the marker altogether. That is a larger change with a
different risk profile, because it has to decide what a hand-added Dock item
means, and answering "remove it" is the same data loss by another route. Worth
doing deliberately, not as a side effect of turning a list into a file.

## Consequences

Editing the Dock takes two steps, and `README.md` says so.

A row skipped because its path does not exist is still covered by the marker, so
a mistyped path stays inert until the next reset. That is how
`/Applications/System Settings.app` — a path macOS has never had — survived in
the installer unnoticed. `tests/dock_install_test.sh` now pins the behaviour, so
it is a choice rather than an accident.
