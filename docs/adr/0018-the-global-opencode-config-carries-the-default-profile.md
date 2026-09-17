# The global OpenCode config carries the default profile

`opencode/opencode.jsonc` holds the payload of the profile `opencode/env.zsh`
names as the default, inside a `// generated: default-profile` block that
`_scripts/render-opencode-profiles` writes. The rest of the file stays
hand-authored.

Until now the global file deliberately held no routing. Model selection lived
in `opencode/profiles/_routing.tsv`, the renderer composed it into each
profile's payload, and a launcher exported `OPENCODE_CONFIG` so that payload
merged over the global one. A profile owned every route; the global file owned
what every profile shares.

The `opencode-desktop` app breaks that arrangement in a way no launcher can
repair. It embeds the runtime rather than spawning a CLI, so `ocx opencode` and
`bin/opencode-profile` are both out of the path, and it has no profile
selector. A `.app` opened from the Dock inherits no environment, so
`OPENCODE_CONFIG` never reaches it. It reads `~/.config/opencode` and finds
MCP servers, plugins, the orchestrator and permissions — and no model, for
itself or for any agent the orchestrator delegates to.

## Considered options

Setting the variable for the GUI session with `launchctl setenv` reaches the
app, and reaches every other graphical application on the machine at the same
time. A per-machine environment that one app needs is not something to install
globally and then have to remember.

A wrapper `.app` that execs `bin/opencode-profile` would keep the routing in
the profiles, at the cost of a second application bundle to build, sign, keep
beside a cask Homebrew updates, and point the Dock at. That is a large amount
of machinery to carry one environment variable.

Copying the default routes into the global file by hand is the shape this
repository spends the most effort avoiding: two places to change a model, and
nothing that notices when only one of them is changed.

Leaving it unrouted and choosing the model in the app's own interface was the
option that touched nothing. It covers the session's main model and leaves
`coder`, `reviewer`, `explore`, `researcher` and `scribe` unrouted, which is
most of what the orchestrator does.

## Consequences

The global config is now partly generated, which it was not before. The block
is delimited the way the README's generated tables are, the renderer refuses a
file whose markers are missing or unterminated, and `--check` reports drift, so
an edit between the markers is caught rather than silently overwritten.

Nothing about the CLI changes. `OPENCODE_CONFIG` merges a profile **over** this
file, so `anthropic`, `go` and `xing` still replace every route they declare,
and `regular` merges values identical to the ones already there. The floor is
only reached by a host that supplies no profile at all.

The renderer now reads `opencode/env.zsh` for `OCX_PROFILE` and refuses a
default with no roster entry. That is one more reason `env.zsh` must stay
POSIX-sourceable; `bin/opencode-profile` already depended on the same property.
Which profile a machine runs by default stays declared exactly once.

Changing a route remains a single edit to `profiles/_routing.tsv` followed by
the renderer. Changing which profile is the default is a single edit to
`env.zsh` followed by the renderer, and the global floor follows it.
