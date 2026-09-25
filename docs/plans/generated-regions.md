# Shared generated-region reader

Accepted design from the Candidate 03 interview, confirmed by the repository
owner. Implemented in `_scripts/generated-region.sh`, covered by
`tests/generated_region_test.sh` and, at the renderer commands,
`tests/generated_renderer_test.sh`.

Canonical implementation spec:
[issue #40](https://github.com/danilomartinelli/dotfiles/issues/40), labelled
`ready-for-agent`.

Markdown and JSONC duplicated the state machine that replaces generated regions
inside hand-authored files. That responsibility is now shared, while content
generation stays in the renderers and comparison, writing, and `--check` stay in
`_scripts/generated-file.sh`.

## Interface and ownership

The private module `_scripts/generated-region.sh` exposes one entrypoint:

```bash
generated_regions_render <markdown|jsonc> <source-file> <handler>
```

The handler receives a region name and prints its replacement body as complete,
newline-terminated lines, or prints nothing for an empty body. This is the
existing generators' contract; JSONC adds no separator before the closing
marker. The module owns marker recognition, region structure, format-specific
padding, and copying the text outside region interiors. It does not know
catalogs, profile routing, or which names a handler supports.

- Preserve manual text and marker lines byte-for-byte, including whether the
  last line ends with a newline. Change only region interiors.
- Allow sequential regions with the same name. Call the handler once for each
  occurrence, in file order.
- Require at least one actually recognized region; a marker mentioned inside
  ordinary text does not satisfy that requirement.
- Preserve the last manual line even when it has no terminating newline.
- Retain the current output for valid existing files, including Markdown's
  blank lines around the generated body and JSONC's lack of extra padding.

## Marker recognition and failures

| Format   | Opening marker               | Closing marker           | Recognition                      |
| -------- | ---------------------------- | ------------------------ | -------------------------------- |
| Markdown | `<!-- generated: <name> -->` | `<!-- generated-end -->` | Exact lines, without indentation |
| JSONC    | `// generated: <name>`       | `// generated-end`       | Leading indentation is accepted  |

Do not trim names, normalize whitespace, or broaden recognition. Names must be
nonempty; the handler decides which names it recognizes. Text that does not
match the format's marker syntax stays ordinary text. A recognized opening
must have a recognized closing marker.

Refuse an empty name, nested opening, orphan closing, unterminated region,
unreadable source, or failed handler. Diagnostics go to stderr and the function
returns failure to its caller. Invalid invocation returns status 2; rendering
failures return status 1.

The module emits rendered text progressively on stdout. A failure can therefore
leave partial output, which callers must discard. Existing callers already
render into a temporary file and sync that file only after success. Keep this
per-file guarantee; previously written files are not rolled back when a later
file fails, and the module adds no second buffering layer.

## Integration and validation

- Replace both readers with the shared interface. Keep table generation in
  `_scripts/markdown-table.sh` and JSONC content generation in the OpenCode
  renderer. No configurable syntax adapters or compatibility modes are needed.
- Move region scenarios into a shared interface suite exercised for both
  formats. Retain table-only scenarios and the renderer integration tests.
- Cover all structural refusals, the two reproduced defects, repeated names,
  exact preservation, format-specific spacing, handler failure, and idempotence.
  Verify that a failed render does not publish that file.
- Preserve [ADR-0018](../adr/0018-the-global-opencode-config-carries-the-default-profile.md):
  the global JSONC still carries the declared default profile, and routing and
  the write/check behavior remain unchanged.
- Complete applicable static checks and `_scripts/test` when implementing.
  Documentation validation does not establish that the new reader exists.
