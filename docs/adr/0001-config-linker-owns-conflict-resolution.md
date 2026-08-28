# The config linker owns conflict resolution

Topic installers declare what an existing target *is* by selecting a conflict
policy; `_scripts/link-config` decides what happens to it. An installer that
clears a target itself defeats the policy it then asks for, so every removal
belongs to the linker.

## Considered options

The OpenCode installer previously removed each target with `rm -rf` before
calling the linker. That was simpler and kept the destruction next to the code
that understood why it was safe, but it left the linker running its default
`replace-with-backup` policy against a path that no longer existed. The
interface promised a backup that could never be produced, and a real file at a
managed path was lost silently. Adding a `replace-generated` policy moves the
removal behind the one interface that fixture tests can reach.

## Consequences

The linker now performs an unattended `rm -rf` on a caller-supplied path, which
is why `replace-generated` refuses to remove the filesystem root, the home
directory, or any directory containing the source about to be linked. That last
rule stops a checkout from deleting itself without teaching the linker where
checkouts live.
