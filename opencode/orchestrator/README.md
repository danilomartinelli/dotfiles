# Orchestration runtime

`index.ts` replaces the two upstream workspace/delegation hooks and the
standalone memory plugin entry. `regular.ts` coordinates the authored
workflow. `session-journals.ts` resolves native parent/project identities,
`delegations.ts` owns the persisted lifecycle, `artifacts.ts` prepares coder evidence storage, `permissions.ts`
classifies orchestration tools and enforces query capabilities, `redirect-bounds.ts` keeps writer shell logs
bounded, `prompts.ts` states role responsibilities, and
`memory/` adapts the pinned memory storage without automatic extraction.

Both managed profiles use this runtime and their declared model/variant routes.
New requests, resume and native compaction preserve that route; titles are
deterministic. See [the user guide](../README.md#models-and-roles) for the role
roster and [the orchestration contract](../ORCHESTRATION.md) for workflow and
permission rules.

MCP query names are declared once in `permissions.ts` and used by both the
native role permissions and the runtime guard. When a configured server changes
its tools, inspect its live `tools/list` response and input schemas, then update
the approved queries and isolated fixtures together. Do not infer capabilities
from a server prefix or a `readOnlyHint` annotation alone.

Orchestration and memory tools are classified once in `permissions.ts` too, and
the native role permissions and the runtime admission hook both read that
classification. Native `task` routing is denied to every role. The root
orchestrator alone may delegate, list, cancel, snapshot for review, save plans,
write todos, ask questions, compress, call `memory_commit`, and create or
delete worktrees. Every role may read a known delegation of its own root, the
saved plan and todos, and query memory. A role answer is not identity: the
hook and `delegation_list` still prove a root-only call comes from a root
session before recovering or enumerating anything, and delegation ownership
still bounds what a writer may change. `memory` accepts `search`, `list`,
`profile` and `help` without `content`, and its schema enumerates the same
modes. The hook and the memory executor both enforce that rule, because
automatic retrieval calls the executor directly. The worktree plugin's two
tools are granted by name, so a tool added under that prefix stays denied at
both boundaries until it is classified deliberately. Tools outside this
classification keep their existing guards.

OpenCode's native MCP resource listing, template listing and resource reading
use the `read` permission. The runtime query guard recognizes all three
operations independently of the server tool allowlist. Keep the native fixture
covering discovery followed by reading a returned URI; tool-only fixtures do
not exercise this path.

## Lifecycle

The project database under `~/.local/share/opencode/orchestrator/` contains
delegation records, routes, retained results and plans. It is separate from
OpenCode's internal database and uses OpenCode's stable project ID across
worktrees. A child in a different project still uses the root project's journal
for ownership, tool acknowledgements, results, cancellation and recovery.
Resolution checks the native parent and directory against the recorded child;
an unregistered child cannot inherit a root's capabilities. Existing journals
stay in place. No runtime data belongs in this repository.

Reservations are atomic across processes using the same root project journal.
Use one root to coordinate work spanning repositories; independent root projects
do not share reservations. At most three children run per root.
Writers sharing that journal cannot claim overlapping canonical paths,
including across roots; reviewers and writers cannot overlap in the same
worktree. Writers must honor ownership in shell commands too; the hook checks
native edit/write/apply_patch targets (including move destinations), but does
not provide an OS sandbox for shell writes. One shell shape is bounded
explicitly: a writer pipeline that runs a non-terminating command and
redirects into a file with no byte cap is rejected before execution, because
a dev server looping on an error fills the disk long before anyone reads the
log. The rejection names the bounded form. `ghead -c` from coreutils caps a
live stream and stops the producer at the cap; BSD `head` rejects size
suffixes, so a bare `head -c 500M` fails on macOS. `tail -c` bounds the file
when only the final output matters. The guard requires boundedness, not a
particular size, and accepts a command-wide `ulimit -f`; note that
RLIMIT_FSIZE counts 512-byte blocks and kills the process with SIGXFSZ on
every file it writes, not only the log. Its markers are a deliberately
narrow list of runner scripts, watch flags and known servers; the guard is
not a general shell sandbox and misses shapes it does not name.
Read-only roles have a fail-closed tool/argument guard. Explicitly enabled
coder MCP calls join the same execution ledger as native writes and shell calls.

Only the root build/plan may create, resume or cancel a child. Resume keeps its
role, directory, work item and route. If a profile update changes that route,
finish the old execution before starting a new delegation for the remaining work.
A generation ID protects resumed work
from delayed completion events. Terminal status requires a final assistant
result; a completed tool-call step does not release ownership.

Each new or resumed delegation receives a 30-minute deadline. Existing executions
keep their recorded deadline, including after a process restart.
Cancellation and deadline expiry call OpenCode's abort API, verify the
session identity and wait for actual native tool completion acknowledgments.
Rejected tools can skip OpenCode's completion hook; their persisted error
records reconcile the ledger during normal completion and stopping alike.
Only actual tool errors count: an `interrupted` placeholder retains its reservation.
The API's idle/interrupted state alone is insufficient: shell cleanup can
continue after it. Missing acknowledgments stay `stopping`, retain the
reservation and report the diagnostic. Recovery inspects existing sessions; it never starts replacement
children. A creation interrupted before its child ID was recorded needs
session inspection and explicit reconciliation; no speculative restart occurs.
Destroying a root or child session outside the orchestrator does not clear the
project journal. Recover therefore treats a missing root or child as terminal,
releases its ownership, and records the diagnostic, so a new root is not stuck
behind `review_snapshot` or path overlap forever. Recover also inspects every
active row in the journal: a finished child is settled and a past-deadline
writer is timed out even when a different root triggered recovery. A living
session still cannot cancel another root's in-deadline writers; only absence,
settlement or deadline expiry releases them.

Recovery belongs to the `Delegations` operations that need it, not to their
callers. Starting or resuming a delegation, refreshed listing and reading,
review snapshots, collecting notifications for a root message, compaction
context and memory consolidation each recover the journal before their own
checks, so an adapter never runs a separate preparation step. Resolving a
session's journal, a child's identity, a role or a permission is a local
observation: it reads the journal as recorded and never stops an expired child
or delivers a notice. A notice delivered because recovery stopped a child
consumes the recorded state without recovering again. Consolidation recovers
before its lifecycle reservation, outside the transaction, so a failed memory
write cannot undo recovery. Preparing an operation does not serialize it with
another root's.
For remote MCP calls, OpenCode 1.18.30 forwards abort to the client. That can
reject the local promise before the server finishes, suppressing the native
completion hook. A cancelled MCP call then remains `stopping` even if the server
later responds. Inspect the remote operation and confirm termination before
explicit reconciliation; a returned abort or elapsed time is not proof. Normal
MCP completion acknowledges the ledger and releases the reservation.

Results remain readable after compaction. Successful results are batched when all
children settle. Failures, timeouts and pending stops wake the existing root even
while siblings remain active. A pending stop is reported once, then terminal
status receives its own notice after acknowledgments arrive. Notification claims
include the generation and status so a failed delivery cannot rearm an older
resume. These notifications create no extra session and never release ownership.
The root inspects partial work and resumes the same terminal delegation within
existing authorization; an unresolved stop allows only independent work.
The first root message, each delegated generation and compaction supply the
native session directory. `read-context.ts` anchors relative file queries there
and reports missing targets with rediscovery guidance. Existing external paths
still go through OpenCode's native permissions; missing targets are never
silently replaced by similarly named files.

## Artifacts and review snapshots

Each coder in a Git checkout receives
`.opencode-artifacts/<delegation-id>/` inside its delegation directory. The
runtime reserves that path alongside its explicit writable scope, prepares it
before prompting the child and reuses it on resume. A coder request with
`ownership: []` is valid in Git: the artifact directory is its entire writable
scope, suitable for verification or explicitly permitted MCP work. Source,
configuration and documentation writes still require their own declared paths.
Scribe and coder outside Git require explicit ownership. Directory ownership
includes descendants; a trailing `/**` is normalized to that directory, while
other glob patterns are rejected before creating a child.

The artifact directory has its own managed `.gitignore`. The runtime preserves
the project's ignore files, refuses symlinks and tracked artifact content, and
keeps unrelated files in the parent directory visible to Git. Use this directory
for generated logs, screenshots, downloads and diagnostic scripts; source and
deliverable documentation remain in their normal paths. Artifacts are retained
after completion and cancellation. Removal requires authorization; no automatic
cleanup or external-directory write access is granted.

`review_snapshot` waits for writers affecting that checkout, including pending
stops. Read-only investigations and writers in unrelated checkouts do not block
it. An enabled CodeGraph prepares the checkout only after that check passes and
before hashing, so a refused snapshot neither indexes nor hashes anything. The snapshot hashes HEAD, tracked changes and non-ignored untracked content;
a changed snapshot invalidates the review verdict. Pass the full returned value
unchanged to every reviewer of that version.

Untracked source is bounded at 1,000 files and 16 MiB. Limit errors report file
count, size and the largest paths; metadata samples at most 10,000 files. They
preserve all files. For generated evidence left elsewhere, resume its owning
coder to verify and relocate it into its artifact directory, then update
references and retry. Keep actual source visible to Git. Ignored evidence is
outside the source hash: reviewers must report which evidence they used and
material verification gaps, and its owner must preserve it during review.

## Code navigation

`read-context.ts` also anchors native LSP file paths. The profile enables
language servers; the launcher exposes the experimental tool; role permissions
and the query guard allow its navigation operations. These are separate gates.

`codegraph.ts` owns the fixed Git-project startup hook and CodeGraph query
targeting. It runs only while the CodeGraph MCP is enabled. First messages and
review snapshots await preparation; queries also check it before reaching the
MCP. Preparation resolves the native session directory through Git, independently
of the runtime's main worktree. Explicit query paths outside that checkout are
rejected instead of falling back to another index.

A process shares one preparation promise per canonical checkout. Atomic
directory creation claims a missing index across processes; the pinned CLI
accepts that empty directory. Existing directories never trigger automatic
initialization, even when incomplete. Initialization uses a closed stdin and
three-minute timeout. Failure is retained for the process lifetime and partial
data remains available for explicit repair. Another process that observes an
incomplete index falls back to file/LSP queries; start a new process after the
index is ready. There are no Git commit hooks, background LLM requests or new
delegation roles for indexing.

Git ignore checks honor global excludes before appending a root-only project
pattern. The hook refuses index/ignore symlinks and reports tracked index files
without untracking them. MCP auto-sync may update the local index while agents
query it; the read-only boundary protects source edits. The
[user guide](../README.md#code-navigation-lsp-and-codegraph) owns installation,
opt-out and recovery instructions.

## Memory

The regular adapter retains the baseline UI and read tool, but drops the
upstream idle, prompt-capture and profile-learning hooks. It injects at most
three historical memories on the first root message and preserves the
baseline's retrieval after compaction. Neither path creates a session or calls
an LLM. Prompt history is not duplicated in the memory database.

`memory_commit` writes a consolidated outcome directly into the existing
project memory shard. A deterministic ID covers project, work item and outcome.
One SQLite transaction checks the immutable content/evidence fingerprint and
inserts the memory. Exact retries return the same ID; changed decisions need
a new outcome ID. Embeddings run locally through the pinned baseline.
Consolidation holds a SQLite reservation over the project lifecycle until
storage settles, preventing a concurrent child start. A process crash releases
that reservation automatically; storage retry remains idempotent.

The adapter uses the project's first shard for stable identity. New captures
fail at `maxVectorsPerShard` instead of silently rotating. Existing retries
remain valid; a shard-count update failure is repairable by retrying the same
outcome. Capture failures do not invalidate verified implementation results.
The root reports the failure without generating another summary.

## Dependencies and updates

`package.json` and `bun.lock` pin dependencies, including OpenCode Mem 2.26.0
and the SDK matching OpenCode 1.18.31. The private memory storage adapter checks
the exact package version before importing its internal modules. Do not update
the memory version without checking its schema, exports and transaction seam.

For a dependency update, review the release and internal storage interfaces,
update through Bun, review the lockfile and rerun native, lifecycle and memory
fixtures. Worktree and notification components remain under OCX ownership;
validate their integrity with `ocx verify` after updates.

```bash
bun install --frozen-lockfile --ignore-scripts --cwd opencode/orchestrator
_scripts/test opencode_orchestrator
bun run --cwd opencode/orchestrator format:check
```

The [validation contract](../ORCHESTRATION.md#validation-and-maintenance)
describes the behavior these fixtures cover.
