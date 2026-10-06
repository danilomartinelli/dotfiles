---
status: accepted
---

# Isolate upgrade effects and source publication

For [issue #66](https://github.com/danilomartinelli/dotfiles/issues/66), controlled
upgrades will receive three explicit adapters: command execution, OSV queries,
and terminal interaction. The managers retain response interpretation and
upgrade rules. Separate adapters keep subprocess results, advisory lookups,
and owner selection from becoming one general-purpose operating-system
interface. Command execution preserves the distinction between captured
queries and installations that inherit the terminal. Mise continues through
the policy owner established by
[ADR-0006](0006-own-mise-policy-without-changing-project-behavior.md).

A private staging module will own source snapshots, temporary copies,
concurrent-edit checks, publication, and restoration after a publication
failure. It will know nothing about Mise, lock formats, or upgrade candidates;
the Mise manager retains selected-version and unselected-entry validation.
This preserves the source-protection boundary of
[ADR-0001](0001-controlled-software-upgrades.md): check content before publishing
and attempt to restore already-published files if a write fails. It does not
provide atomic publication across files, recovery after process termination,
or coordination between concurrent writers. Installed software and subsequent
installer effects remain outside source rollback.

If publication fails, restoration will attempt every already-published file,
even when an earlier restoration fails. The operation will report the original
publication error, all restoration failures, and the paths left unrestored,
then fail without claiming complete recovery. Stopping at the first restoration
error would abandon files that could still be recovered and hide the initial
failure.

Before the first publication write, the original bytes of every file to be
published will be saved in a separate temporary recovery area. The staged
versions cannot serve as that backup because preparation has already changed
them. Successful publication or complete restoration removes the recovery
copy. Incomplete restoration retains it and reports its location for recovery.
This intentionally leaves an artifact for the owner to remove after recovery;
it does not add automatic resumption or a crash-recovery protocol.

The protected inputs will include `Brewfile` as well as `mise/config.toml`,
`mise/mise.lock`, and `README.md`. Only the latter three are published or
restored. Rendering consumes `Brewfile`, so accepting its concurrent modification
could publish a catalog based on obsolete declarations. Aborting publication
when it changes is an intentional correction alongside the refactoring; the
owner's edit is preserved.

Upgrade orchestration tests will use in-memory adapters for selection,
requery, and application order. Direct staging tests will use temporary files.
One isolated subprocess smoke case will retain coverage of the entrypoint,
production adapters, and Mise policy composition. The shared fake Mise remains
available to its other suites; upgrade-specific hooks move out of it as their
scenarios gain direct coverage. This avoids maintaining a package-manager
simulator for each orchestration case while still checking the production
wiring.

Commands such as lock generation and catalog rendering produce files as well
as command responses. Their in-memory test adapters will materialize explicit
file fixtures when the expected command runs. Production parsing and validation
will consume those fixtures, including intentionally invalid results, rather
than relying on a second implementation of the resolver or renderer. Direct
staging coverage will include publication failure, restoration that continues
after an error, preservation of the original error, and recovery-copy cleanup
or retention according to the outcome.

Discovery and advisory reporting without a terminal, explicit confirmation,
requery before installation, and application order remain as specified in
ADR-0001 and the maintenance guide.
