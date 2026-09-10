# Orchestration runtime

`index.ts` replaces the two upstream workspace/delegation hooks and the
standalone memory plugin entry. `regular.ts` coordinates the authored
workflow. `delegations.ts` owns its persisted lifecycle, `permissions.ts`
enforces query capabilities, `prompts.ts` states role responsibilities, and
`memory/` adapts the pinned memory storage without automatic extraction.

Both managed profiles use this runtime and their declared model/variant routes.
New requests, resume and native compaction preserve that route; titles are
deterministic. See [the user guide](../README.md#models-and-roles) for the role
roster and [the orchestration contract](../ORCHESTRATION.md) for workflow and
permission rules.

## Lifecycle

The project database under `~/.local/share/opencode/orchestrator/` contains
delegation records, routes, retained results and plans. It is separate from
OpenCode's internal database and uses OpenCode's stable project ID across
worktrees. No runtime data belongs in this repository.

Reservations are atomic across processes. At most three children run per
root. Writers in the same project cannot claim overlapping canonical paths,
including across roots; reviewers and writers cannot overlap in the same
worktree. Writers must honor ownership in shell commands too; the hook checks
native edit/write/apply_patch targets (including move destinations), but does
not provide an OS sandbox for shell writes.
Read-only roles have a fail-closed tool/argument guard. Explicitly enabled
coder MCP calls join the same execution ledger as native writes and shell calls.

Only the root build/plan may create, resume or cancel a child. Resume keeps its
role, directory, work item and route. A generation ID protects resumed work
from delayed completion events. Terminal status requires a final assistant
result; a completed tool-call step does not release ownership. A source
snapshot includes HEAD, tracked changes and untracked content; a changed
snapshot invalidates the review verdict.

Cancellation and the 15-minute deadline call OpenCode's abort API, verify the
session identity and wait for actual native tool completion acknowledgments.
The API's idle/interrupted state alone is insufficient: shell cleanup can
continue after it. Missing acknowledgments stay `stopping`, retain the
reservation and report the diagnostic. Recovery inspects existing sessions; it never starts replacement
children. A creation interrupted before its child ID was recorded needs
session inspection and explicit reconciliation; no speculative restart occurs.
For remote MCP calls, OpenCode 1.18.23 forwards abort to the client. That can
reject the local promise before the server finishes, suppressing the native
completion hook. A cancelled MCP call then remains `stopping` even if the server
later responds. Inspect the remote operation and confirm termination before
explicit reconciliation; a returned abort or elapsed time is not proof. Normal
MCP completion acknowledges the ledger and releases the reservation.

Results remain readable after compaction. Notifications are batched when all
children settle and continue the existing root session.

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

`package.json` and `bun.lock` pin dependencies, including OpenCode Mem 2.25.0
and the SDK matching OpenCode 1.18.23. The private memory storage adapter checks
the exact package version before importing its internal modules. Do not update
the memory version without checking its schema, exports and transaction seam.

For a dependency update, review the release and internal storage interfaces,
update through Bun, review the lockfile and rerun native, lifecycle and memory
fixtures. The installer removes retired components through OCX, preserving modified files.
It can force receipt cleanup only after proving all recorded payloads absent.
Worktree and notification components remain under OCX ownership.

```bash
bun install --frozen-lockfile --ignore-scripts --cwd opencode/orchestrator
_scripts/test opencode_orchestrator
bun run --cwd opencode/orchestrator format:check
```

The [validation contract](../ORCHESTRATION.md#validation-and-maintenance)
describes the behavior these fixtures cover.
