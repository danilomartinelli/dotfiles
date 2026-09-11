# OpenCode orchestration contract

The orchestration plugin coordinates bounded work through declared roles,
resumable delegations and consolidated memory. OCX supplies profile assembly,
worktree management and notifications; the local runtime owns the workflow.

## Roles and routing

`plan` coordinates planning and `build` coordinates implementation. Both handle
short read-only queries directly and delegate work when an independent focus
justifies another execution.

- `coder` implements and verifies a bounded scope.
- `reviewer` checks a supplied focus against a stable source snapshot.
- `scribe` writes documentation from verified source and settled decisions.
- `explore` investigates the codebase without changing it.
- `researcher` retrieves primary documentation and tracker context.

Supporting roles are optional. Specialized work uses a focus in the delegation
prompt rather than a separate agent type. Profiles own model and variant
selection; delegations cannot override them. The routing source is
`profiles/_routing.tsv`, with the generated table in
[the OpenCode guide](README.md#models-and-roles).

## Delegation and review

1. Establish the objective, completion criteria, directory and existing user
   authorization. Reuse known facts and settled decisions.
1. Give each delegation one focus, a stable work-item identifier, relevant
   references, constraints and required verification. Writers receive explicit
   writable paths; read-only roles receive no ownership.
   The native session's directory is the path base. A child in another project
   keeps its lifecycle in the root project's journal. Resume and compaction
   recover that association and the actual directory.
   In Git checkouts, coder also receives a private, ignored artifact directory
   inside its writable scope. Preserve generated evidence there and keep source
   and deliverable documentation in their normal paths. See
   [artifacts and snapshots](orchestrator/README.md#artifacts-and-review-snapshots)
   for limits and recovery.
1. Start one useful child. Add independent parallel focuses when needed, up to
   three active children per root. Writers require disjoint paths and agreed
   interfaces. Reviewers run after writers finish against the same snapshot.
1. Collect results through notifications and retained delegation records.
   When only active children remain to be awaited, give one concise progress
   update and end the current response. The task stays pending; the runtime
   batches successful results after children terminate and wakes the same root
   on failures, timeouts or pending stops. After confirmed termination, inspect
   partial work and resume the same delegation within existing authorization;
   a child failure alone does not require another user message. A pending stop
   retains ownership while independent work can continue. Do not wait
   through shell sleeps, repeated status/file checks or another delegation.
   Resume the same delegation for corrections to its work item and focus.
1. Consolidate duplicate findings. A blocker identifies a violated contract,
   a reachable failure and precise evidence. Review output omits praise, empty
   categories and repeated findings.
1. After correction, resume only affected review focuses with the new snapshot,
   the delta and completed checks. There is no fixed number of review rounds.
   Planning and verification without changes do not trigger automatic review.
1. Finish with the outcome, checks actually performed and material gaps.
   Technical verification does not imply human acceptance or authorization
   to publish, merge or deploy.

## Permissions and integrations

Build/plan, reviewer, explore and researcher have a read-only tool and argument
boundary. Supported shell inspections reject mutation, command composition and
external-program escapes. Repository and tracker queries discover the remote
and matching `gh`/`glab` CLI before falling back to web access.
Queries remain valid when the guard's normalized command is reused; each call
revalidates its executable and arguments. Leading environment assignments must
use the query's approved safety values. Partial or reordered assignments are
accepted and normalized to the complete safety environment before execution.
Single-quoted filters remain literal arguments; they cannot compose shell
commands. Tracker APIs accept GET queries and a literal `Accept` header.
Built-in tracker help is available through `gh help api`, `glab help api` and
trailing `--help`/`-h` on supported tracker topics. Independent queries use
separate tool calls; filters use the CLI's `--jq` option. Downloading/extracting
artifacts or saving output belongs to coder with an owned destination, preferably
as part of existing relevant work. Reviewers receive the resulting evidence.
`command -v NAME` can discover any literal executable name without running it.
Git inspections include short log counts, revision comparisons, the current
branch, branch listings and source grep. GitLab queries also support MR branch
filters and API `json`/`ndjson` output formatting. Remote transports such as `ls-remote` require coder;
read-only roles use tracker API queries for remote refs.

File queries resolve relative paths against the native session directory.
Missing paths report that directory and call for local rediscovery. The runtime
does not infer another worktree path, redirect a file request or broaden native
external-directory permissions.

The native role permissions and query guard share one explicit MCP tool list
for CodeGraph exploration, Context7 documentation, Exa search/page retrieval and
grep.app code search.
Unknown tools are denied by default, including new tools under those server
names; a server prefix alone does not authorize a query.

Native LSP navigation is enabled in the profiles and permitted for every role.
CodeGraph queries select the session's actual Git checkout explicitly, including
linked worktrees. Prompts use these tools when they answer the current question;
file reads remain available for unsupported languages or stale index results.

The fixed CodeGraph startup hook is authorized local index maintenance: it
initializes a missing `.codegraph/` directory once and adds a project ignore
only when Git does not already ignore it. This narrow setup can run before
agent work, including planning, without granting shell writes to read-only
roles. It completes before review snapshots and creates no LLM sessions.
See [code navigation](README.md#code-navigation-lsp-and-codegraph) for opt-out,
concurrency and recovery behavior.

Project scripts and runtime/package-manager commands belong to coder, even
when a subcommand is named `docs` or `list`. The root includes necessary script
execution in a relevant coder delegation; read-only leaves return that need
to the root. A policy rejection calls for a supported tool or role, without
repeated attempts using wrappers or alternate command spellings.

Coder and scribe native writes are checked against canonical owned paths.
Coder must respect that ownership in shell commands too; scribe has no shell
execution. The runtime is not an operating-system sandbox for writer commands.

Additional MCPs and skills belong to trusted project configuration. Explicit
coder MCP permissions do not broaden the read-only roles or authorize remote
changes. Project instructions cannot replace the profile's declared routes.

Cancellation and timeout retain reservations until tool completion is
acknowledged. Missing acknowledgement leaves a delegation in `stopping`;
recovery inspects existing executions without creating replacements. See
[the runtime lifecycle](orchestrator/README.md#lifecycle) for remote MCP
cancellation limits and reconciliation requirements.

## Memory

The root synthesizes durable decisions or verified solutions in its existing
execution after all children terminate. `memory_commit` stores the summary
with evidence and a stable project/work-item/outcome identity. Identical
retries reuse the stored outcome; a changed decision requires a new outcome.
Routine facts and provisional attempts remain in session history.

Automatic extraction, profile learning and raw prompt capture are disabled.
Memory and metadata create no auxiliary LLM sessions. Existing memory data,
retrieval and UI remain available. Storage failures are reported separately
without regenerating the summary or invalidating verified implementation work.

## Validation and maintenance

Native OpenCode fixtures exercise role discovery, profile routing, project
configuration, parallel and cross-project delegation, resume, cancellation,
path recovery, native LSP and MCP permissions. CodeGraph fixtures exercise the
installed CLI/MCP, Git-root selection, worktrees, concurrent initialization and
preservation of existing indices and Git data.
Memory fixtures cover direct storage, idempotent retries and the absence of
automatic LLM subsessions. Installer fixtures cover repeated installation,
competing-hook rejection and preservation of custom configuration.

Run the focused checks from [the OpenCode guide](README.md#update-and-verify).
[The runtime guide](orchestrator/README.md) owns lifecycle details, storage
limits and dependency updates. Configuration changes take effect in new
OpenCode processes.
