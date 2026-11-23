# Herdr

The Estro layout and its eight mods come from
[herdr-mods at `bad7512`](https://github.com/munza/herdr-mods/tree/bad7512b6148b7092068cd3a6478c45706731c18/estro).
The bundled runtime sources and upstream notices live in `estro/`.

## Installation

The topic installer links the layout and installs a copy of each missing mod
with its assets. It uses the declared Mise Go toolchain to build the Branch PR
and Branch Issue helpers locally. Existing mod directories are preserved,
including their settings.

## Using Estro

Select Estro in Herdr or run
`herdr-app do layout.switch '{"name":"estro"}'`. Its shortcuts only apply
while Estro is active. The right panel offers Files, Changes, Pull Requests,
and Issues. The GitHub panels use authenticated `gh`. Branch Issue defaults
to Linear and uses `LINEAR_API_KEY` when available. To browse GitHub Issues
instead, select GitHub in Mod settings.

The installer adds the Estro shortcuts to the keys file while preserving
existing bindings. Symlinked keys files stay under their existing
owner. The bindings for those files are in `estro/keys.json`. On a fresh
machine, launch Herdr once to generate the default keys, then re-run
`herdr/install.sh` to add the Estro shortcuts.

| Shortcut    | Action                 |
| ----------- | ---------------------- |
| Cmd+Alt+P   | Search                 |
| Cmd+Alt+,   | Mod settings           |
| Cmd+Shift+E | Focus Files            |
| Cmd+Shift+B | Toggle the right panel |
