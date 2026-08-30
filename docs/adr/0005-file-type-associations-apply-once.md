# File-type associations apply once

Applying an association catalog is a run-once step in every topic that claims
file types. `archiver`, `skim`, and `zed` each gate `installer_apply_associations`
behind `<topic>-associations` and reapply only on
`DOTFILES_RESET=<topic>-associations dot`.

The state being protected is not a layout but the defaults a person set in
Finder. "Open With → Always" is a deliberate local decision that this repository
never learns about, and an update run that silently takes `.pdf` back from
Preview or `.zip` back from The Unarchiver overrides it without saying so. That
is the same class of loss the Dock marker exists to prevent, so it gets the same
answer.

## Considered options

Leaving `archiver` and `skim` reapplying every run was the status quo, and it
had one real argument behind it: `duti -s` is additive where the Dock rebuild
opens with `dockutil --remove all`, so re-asserting a row destroys no structure
and a person can simply set the default again. The reasoning in ADR 0004 does
not transfer unchanged.

It does not survive being repeated daily, though. The cost of the Dock rebuild
is paid once and noticed immediately; the cost here is a preference quietly
reverting every morning, which is worse for being small enough to keep
re-fixing rather than diagnose. Since #28 the three topics share one module, so
the alternative was one operation with two behaviours and no principle
separating them — a coin flip waiting to be settled by whoever touched it next.

Hashing the catalog into the marker so an edit reapplies itself was rejected for
the reason ADR 0004 gives: the hash changes on `git pull` as readily as on a
local edit, so a routine update would reassert every row because a remote change
touched one. The harm is smaller here than for the Dock and it is the same
shape, a remote change overriding a local decision.

Marking the step applied at the top of the installer, before the gates, would
wedge the topic permanently. `archiver/install.sh` bails at three points — a
missing app, an invalid signature, a Launch Services registration failure — and
a run that bailed has applied nothing. The marker therefore sits below every
gate and is written only after `installer_apply_associations` returns, which
`tests/archiver_install_test.sh` pins by asserting a failed registration leaves
the step armed.

## Consequences

Editing `<topic>/_associations.tsv` changes what the next apply would set
without setting it. `DOTFILES_RESET=<topic>-associations dot` applies the edited
catalog, and `DOTFILES_RESET=all dot` re-arms every run-once step. Each catalog
says so in its header, because that is where a person editing a row is looking.

Three new user-facing keys exist: `archiver-associations`, `skim-associations`,
and the pre-existing `zed-associations`. ADR 0002 makes those a contract, so
renaming one changes `README.md` in the same commit.

A first run on a machine where the app is present but `duti` is not leaves the
step armed rather than marking it done, because the skip in
`installer_optional_command` returns before the apply. Installing `duti` and
rerunning `dot` therefore still works without a reset.
