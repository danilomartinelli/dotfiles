# The Android vendor parsers stay in the target adapter

`_scripts/mobile-setup-android.sh` holds three things that are not readiness
logic: `android_java_home` and `run_android_tool` resolve a Java toolchain,
`android_avd_state` parses an AVD `config.ini`, and `find_pixel_device` parses
`avdmanager list device` with an embedded awk program. They stay in the adapter.

## Considered options

Splitting them out is the obvious next deepening, and it is why this file
exists: the file reads as several unrelated clusters, an architecture review
will keep saying so, and the answer is not that nobody noticed.

Each of the three is a translation of one vendor tool's output into one fact
this adapter needs. None has a second caller, and none can acquire one: iOS
resolves no Java, has no `config.ini`, and lists no hardware profiles. Moving
any of them behind its own interface produces a module with exactly one adapter
on each side, which is the hypothetical seam this repository declines elsewhere —
`docs/adr/0012-git-identity-setup-stays-in-the-orchestrator.md` records the same
reasoning for a renderer with one caller.

What made the file hard to read was not that the parsers were in it. It was that
the readiness verdict had two shapes, one per Mobile Target, and that the action
they permitted was re-derived six times in one function body under two different
names. That is what moved: the record is now one shape both adapters fill, and
`android_permitted_action` is the only ready rule. The parsers are what remains
after the part that was actually duplicated stopped being duplicated.

The seam that would earn its keep is a different one. `find_pixel_device` and
`android_avd_state` are only reachable by faking `avdmanager` and writing a
`config.ini`, so the ~100 lines of vendor stubs in `tests/mobile_setup_test.sh`
re-encode the SDK layout a second and third time. A fixture builder owning that
layout would pay for itself across those stubs without inventing a seam inside
the adapter. That is worth doing on its own terms.

## Consequences

`mobile-setup-android.sh` stays several times the size of
`mobile-setup-ios.sh`, and the difference is vendor surface rather than
divergent structure. The two adapters are now comparable where it matters: both
fill one record, both name one permitted action, neither prints.

The stub duplication this ADR declines to fix through the adapter stays. It is
the reason `android_avd_state`'s `image.sysdir.1` normalisation and
`find_pixel_device`'s `id: N or "name"` handling are only observable through
fixtures that spell the same layout the module probes.
