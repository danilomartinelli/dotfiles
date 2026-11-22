---
status: accepted
---

# Declare MCP servers once and deliver them through each agent's own door

MCP servers were declared separately in Zed, OpenCode and Claude Code, in three
formats and three states: Context7 was enabled in one and disabled in another.
`agents/_mcp-servers.tsv` is now the one declaration, and `_scripts/mcp-servers`
its one consumer.

The consumer delivers a row in two ways, because the agents keep their
configuration in two kinds of place. Zed's and OpenCode's files are tracked, so
the consumer renders their server member from the catalog and the catalog is
exhaustive there: a server it does not declare is removed, and the removal is a
diff. Claude Code and Codex keep MCP servers in `~/.claude.json` and
`~/.codex/config.toml`, beside account state and project trust this repository
must not track, so the consumer applies their rows through `claude mcp` and
`codex mcp`. There it adds and replaces but never removes: a server someone
added by hand would disappear without a trace, so it is reported instead.

## Considered options

- **Keep the lists by hand and compare them in a test**, as the Homebrew tap
  and trust lists are. Rejected: those two lists cannot derive each other, while
  every MCP declaration here is the same fact in another format.
- **Edit the machine-local files directly.** Rejected: both files are rewritten
  by their agents and carry state this repository has no business parsing.

## Consequences

- The rendered member holds no comments; the reasons live in the catalog.
- Argent stays outside the catalog. OpenCode 1 honours its timeout only in a
  deprecated form directly under `mcp`, which the consumer does not render and
  leaves untouched.
- A row may leave an agent out. Claude Code gets PostHog from its plugin, and
  Codex cannot add an OAuth server without a browser, which setup cannot wait
  for; the checklist names that command.
- Cursor, Grok and Antigravity receive nothing until one of them is used with
  MCP and gains an adapter.
