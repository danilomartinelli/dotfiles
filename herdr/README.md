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
Changes groups bursts of local file activity into one refresh after the writes
settle. While writes continue, the panel polls Git every 10 seconds by default.

In **Spaces** and **Agents**, expand a Codex or Claude Code agent to see its
active native subagents. Each row shows the agent type and a short identifier.
The row disappears when the CLI reports that the subagent stopped. Native
subagents share the parent chat. Children launched with `hc run` have their
own terminals and can still be opened individually.

Start a fresh local CLI session in Herdr after installing the hooks. In Codex,
open `/hooks` and trust the Herdr hooks. The installer preserves an existing
personal `~/.codex/hooks.json`. If you have custom hooks or use a different
`CODEX_HOME`, merge the entries from
[`codex-hooks.json`](codex-hooks.json) into it. For a remote terminal, the
CLI hooks and `hc` run on the terminal's machine.

In **Unstaged**, the arrow beside **+** discards a file's unstaged edits after
confirmation. A partially staged file keeps its staged version. For a new,
untracked file, the trash icon moves it to the checkout machine's Trash after
confirmation using `trash` or `gio trash`.

In Changes, stage the files for the commit and enter a message. The commit
menu remembers your choice of **Commit** or **Commit & Push**. A clean branch
with unpublished commits shows **Push**. A click during a status refresh waits
for that read to finish before checking the push target. With other edits still present,
choose **Push pending commits** from the menu. Push sends only the current
branch to the same branch name on its push remote and sets up tracking on
first publication when needed. **Amend** applies to one commit.

**Generate with Codex** drafts an editable English message from the staged
diff. Choose Claude or Codex in the commit menu. Generation uses the selected
CLI's local login, including for remote worktrees, and sends up to 48,000
characters of the staged diff when clicked. Review the draft before committing.

The PR badge beside a worktree shows pending or failed checks, conflicts, and
whether its PR is ready, closed, or merged. After a merge, close, or reopen in
the PR panel, the sidebar requests a fresh status from GitHub. For changes
made elsewhere, it checks open PRs every 15 seconds and other checkouts
every minute.

In PRs, **Branch** opens the pull request when the current branch has exactly
one. The GitHub panels use authenticated `gh`. Upstream's Branch Issue
defaults to Linear; `estro/mods/branch-issue/mod.json` sets its provider to
GitHub here, which lists the open issues of the active checkout and the ones
linked to its branch. Click an issue title to open it on GitHub. The checkout
icon beside each title creates a branch named from the issue number and title,
links it to the issue with `gh issue develop`, and opens its worktree in a
Herdr space. Click again to return to the same worktree. The robot icon beside
it creates or reopens that same worktree and starts a fresh chat with the
default agent. The first message asks it to implement the issue and includes
the repository, issue number, title and link. Choose the agent in **Findings**
using the arrow beside **Diagnose & Fix**. The branch lives in
the active checkout's GitHub repository, including for issues linked from
another repository. A mod installed before the provider change keeps its
own setting: select GitHub in Mod settings. The `$` prefix in Search still
asks Linear, because the bundled helper only speaks to it.

Open **⋮ → Findings → Code Review** to start a review chat for the active
worktree. The agent receives the review skill and publishes comments and
repository-relative paths through a private temporary directory on the
checkout machine. Reopen Findings to see the report.

Each finding starts checked. Uncheck one to skip it for this fix, or use
**Ignore** to hide it. **Show ignored** lets you restore it. The panel remembers
the report and selection per worktree and branch. **Diagnose & Fix** opens a
new chat with the diagnosis skill and the selected findings. When the agent
publishes its fix report, the panel removes each finding verified as fixed.
Unresolved findings keep their selection. You can reopen the panel or switch
branches while waiting. **Stop waiting** detaches the panel from the current
review or fix report and keeps the findings available for another run.

The arrow beside **Diagnose & Fix** chooses the agent for both actions. The
initial choice is Herdr's most frequently picked installed agent, and the
panel remembers your choice per machine.

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
