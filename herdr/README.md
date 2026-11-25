# Herdr

The Estro layout and its eight mods come from
[herdr-mods at `bad7512`](https://github.com/munza/herdr-mods/tree/bad7512b6148b7092068cd3a6478c45706731c18/estro).
The bundled runtime sources and upstream notices live in `estro/`.

Estro also includes the standalone
[Skillshare panel at `dab6d4f`](https://github.com/runkids/skillshare/tree/dab6d4fe96f30ca1d49a6b5e5f8fa3682b010b24/herdr/skillshare-mod).
Its files and MIT license live in `skillshare/`.

## Installation

The topic installer links the layout and installs a copy of each missing mod
with its assets. It uses the declared Mise Go toolchain to build the Branch PR
and Branch Issue helpers locally. Existing mod directories are preserved,
including their settings.

## Using Estro

Select Estro in Herdr or run
`herdr-app do layout.switch '{"name":"estro"}'`. Its shortcuts only apply
while Estro is active. The right panel offers Files, Changes, Pull Requests,
and Issues. Changes shows working tree edits and commits ahead of the tracked
branch. A clean, fully pushed branch shows **No changes** and **Commits 0**.
In PRs, **Branch** opens the pull request when the current branch has exactly
one. The GitHub panels use authenticated `gh`. Upstream's Branch Issue
defaults to Linear; `estro/mods/branch-issue/mod.json` sets its provider to
GitHub here, which lists the open issues of the active checkout and the ones
linked to its branch, read-only. A mod installed before that change keeps its
own setting: select GitHub in Mod settings. The `$` prefix in Search still
asks Linear, because the bundled helper only speaks to it.

Click **skillshare** beside the tabs to open or close its panel. It uses the
Homebrew `skillshare` CLI to show global and project resources. On a new
machine, run `skillshare init` to choose the source and agent targets before
syncing. The panel can update its installed copy independently.

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
