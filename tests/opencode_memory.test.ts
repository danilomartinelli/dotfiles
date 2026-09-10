import { afterEach, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  commitMemoryOutcome,
  type MemoryOutcome,
  type MemoryStorage,
  type Transaction,
} from "../opencode/orchestrator/memory/store.ts";
import { createRegularMemoryHooks } from "../opencode/orchestrator/memory/hooks.ts";
import { loadMemoryBaseline } from "../opencode/orchestrator/memory/pinned.ts";
import type {
  Hooks,
  PluginInput,
  ToolContext,
} from "../opencode/orchestrator/node_modules/@opencode-ai/plugin/dist/index.d.ts";

const cleanups: Array<() => Promise<void>> = [];
afterEach(async () => {
  while (cleanups.length) await cleanups.pop()!();
});

async function test_storage(capacity = 10) {
  const directory = await mkdtemp(join(tmpdir(), "opencode-memory-test-"));
  const db = new Database(join(directory, "memory.db"));
  db.run(
    "CREATE TABLE memories (id TEXT PRIMARY KEY, content TEXT NOT NULL, metadata TEXT NOT NULL)",
  );
  cleanups.push(async () => {
    db.close();
    await rm(directory, { recursive: true, force: true });
  });
  let gate = Promise.resolve();
  let failInsert = false;
  let failCount = false;
  let syncedCount = 0;
  const tx: Transaction = {
    async execute({ sql, args = [] }) {
      return { rows: db.query(sql).all(...args) as Record<string, unknown>[] };
    },
  };
  const storage: MemoryStorage = {
    project: "opencode_project_fixture",
    directory,
    capacity,
    async withWriteLock(run) {
      const previous = gate;
      let release!: () => void;
      gate = new Promise<void>((resolve) => {
        release = resolve;
      });
      await previous;
      try {
        return await run();
      } finally {
        release();
      }
    },
    async transaction(run) {
      db.run("BEGIN IMMEDIATE");
      try {
        const result = await run(tx);
        db.run("COMMIT");
        return result;
      } catch (error) {
        db.run("ROLLBACK");
        throw error;
      }
    },
    async embed() {
      return new Float32Array([0.1, 0.2]);
    },
    async insert(tx, record) {
      await tx.execute({
        sql: "INSERT INTO memories (id, content, metadata) VALUES (?, ?, ?)",
        args: [record.id, record.content, record.metadata],
      });
      if (failInsert) throw new Error("fixture insert failure");
    },
    async syncCount() {
      if (failCount) throw new Error("fixture count failure");
      syncedCount = Number(
        (
          db.query("SELECT COUNT(*) AS count FROM memories").get() as {
            count: number;
          }
        ).count,
      );
    },
  };
  const input: MemoryOutcome = {
    project: storage.project,
    workItem: "issue-42",
    outcome: "implemented-v1",
    summary: "The authentication boundary now rejects expired sessions.",
    evidence: ["src/auth.ts:42", "bun test auth: passed"],
    tags: ["auth", "tests"],
  };
  return {
    storage,
    input,
    db,
    setFailInsert: (value: boolean) => {
      failInsert = value;
    },
    setFailCount: (value: boolean) => {
      failCount = value;
    },
    count: () => syncedCount,
  };
}

test("test_commit_is_idempotent_with_atomic_evidence_and_stable_identity", async () => {
  const f = await test_storage();
  const results = await Promise.all(
    Array.from({ length: 8 }, () =>
      commitMemoryOutcome(f.storage, f.input, "root-1"),
    ),
  );
  expect(results.filter((result) => result.created)).toHaveLength(1);
  expect(new Set(results.map((result) => result.id)).size).toBe(1);
  expect(f.count()).toBe(1);
  const row = f.db.query("SELECT content, metadata FROM memories").get() as {
    content: string;
    metadata: string;
  };
  expect(row.content).toContain("Evidence:");
  expect(JSON.parse(row.metadata).orchestrator.evidence).toEqual(
    [...f.input.evidence].sort(),
  );
  expect(JSON.parse(row.metadata).sessionID).toBe("root-1");
  expect(
    (
      await commitMemoryOutcome(
        f.storage,
        {
          ...f.input,
          evidence: [...f.input.evidence].reverse(),
          tags: ["tests", "AUTH"],
        },
        "root-2",
      )
    ).created,
  ).toBe(false);
});

test("test_existing_identity_rejects_changed_outcome_without_overwriting", async () => {
  const f = await test_storage();
  await commitMemoryOutcome(f.storage, f.input, "root");
  await expect(
    commitMemoryOutcome(
      f.storage,
      { ...f.input, summary: "A different claim" },
      "root",
    ),
  ).rejects.toThrow("different evidence or content");
  expect(f.count()).toBe(1);
  expect(
    (
      await commitMemoryOutcome(
        f.storage,
        { ...f.input, outcome: "implemented-v2", summary: "A different claim" },
        "root",
      )
    ).created,
  ).toBe(true);
});

test("test_failed_transaction_leaves_neither_memory_nor_receipt", async () => {
  const f = await test_storage();
  f.setFailInsert(true);
  await expect(commitMemoryOutcome(f.storage, f.input, "root")).rejects.toThrow(
    "fixture insert failure",
  );
  expect(f.db.query("SELECT COUNT(*) AS count FROM memories").get()).toEqual({
    count: 0,
  });
  f.setFailInsert(false);
  expect((await commitMemoryOutcome(f.storage, f.input, "root")).created).toBe(
    true,
  );
});

test("test_retry_repairs_count_after_committed_memory_without_duplicates", async () => {
  const f = await test_storage();
  f.setFailCount(true);
  await expect(commitMemoryOutcome(f.storage, f.input, "root")).rejects.toThrow(
    "fixture count failure",
  );
  f.setFailCount(false);
  expect((await commitMemoryOutcome(f.storage, f.input, "root")).created).toBe(
    false,
  );
  expect(f.count()).toBe(1);
});

test("test_capacity_project_and_private_content_fail_closed", async () => {
  const f = await test_storage(1);
  await expect(
    commitMemoryOutcome(
      f.storage,
      { ...f.input, project: "another-project" },
      "root",
    ),
  ).rejects.toThrow("does not match");
  await expect(
    commitMemoryOutcome(f.storage, { ...f.input, evidence: [] }, "root"),
  ).rejects.toThrow("evidence");
  await expect(
    commitMemoryOutcome(
      f.storage,
      { ...f.input, summary: "public <private>hidden" },
      "root",
    ),
  ).rejects.toThrow("private markup");
  await commitMemoryOutcome(f.storage, f.input, "root");
  await expect(
    commitMemoryOutcome(f.storage, { ...f.input, outcome: "another" }, "root"),
  ).rejects.toThrow("shard is full");
  expect((await commitMemoryOutcome(f.storage, f.input, "root")).created).toBe(
    false,
  );
});

function test_context(agent = "build", sessionID = "root"): ToolContext {
  return {
    sessionID,
    agent,
    directory: "/fixture",
    worktree: "/fixture",
    messageID: "message-1",
    abort: new AbortController().signal,
    metadata() {},
    async ask() {
      throw new Error("No permissions in fixtures");
    },
  };
}

function test_hooks(storage: MemoryStorage) {
  const calls: string[] = [];
  let childrenActive = false;
  let consolidationActive = false;
  const baseline: Hooks = {
    async event({ event }) {
      calls.push(event.type);
    },
    async "chat.message"() {
      throw new Error("Raw prompt capture must never be called");
    },
    async "chat.params"() {
      throw new Error("Prompt model recording must never be called");
    },
    tool: {
      memory: {
        args: {},
        description: "fixture",
        async execute(args) {
          calls.push(String(args.mode));
          return JSON.stringify({
            success: true,
            memories: [
              { id: "old-memory", content: "Previously verified result" },
            ],
          });
        },
      },
    },
  };
  const hooks = createRegularMemoryHooks(
    { directory: "/fixture", worktree: "/fixture" } as PluginInput,
    {
      baseline,
      async storage() {
        calls.push("storage");
        return storage;
      },
      async isRoot(sessionID) {
        return sessionID === "root";
      },
      async withConsolidation(_sessionID, run) {
        if (childrenActive) throw new Error("Children are still active");
        if (consolidationActive)
          throw new Error("Consolidation is already active");
        consolidationActive = true;
        try {
          return await run();
        } finally {
          consolidationActive = false;
        }
      },
    },
  );
  return {
    hooks,
    calls,
    setChildren: (active: boolean) => {
      childrenActive = active;
    },
    hasLease: () => consolidationActive,
  };
}

test("test_regular_never_forwards_capture_hooks_and_only_root_gets_retrieval", async () => {
  const f = test_hooks((await test_storage()).storage);
  const output = {
    message: { id: "message-1" },
    parts: [],
  } as unknown as Parameters<NonNullable<Hooks["chat.message"]>>[1];
  await f.hooks["chat.message"]!(
    { sessionID: "child", agent: "coder" },
    output,
  );
  await f.hooks.event!({
    event: { type: "session.idle", properties: { sessionID: "root" } },
  });
  expect(f.calls).toEqual([]);
  expect(f.hooks["chat.params"]).toBeUndefined();
  await f.hooks["chat.message"]!({ sessionID: "root", agent: "build" }, output);
  await f.hooks["chat.message"]!({ sessionID: "root", agent: "build" }, output);
  expect(f.calls).toEqual(["list"]);
  expect(output.parts).toHaveLength(1);
  expect((output.parts[0] as { text: string }).text).toContain(
    "Previously verified result",
  );
  await f.hooks.event!({
    event: { type: "session.compacted", properties: { sessionID: "child" } },
  });
  await f.hooks.event!({
    event: { type: "session.compacted", properties: { sessionID: "root" } },
  });
  expect(f.calls).toEqual(["list", "session.compacted"]);
});

test("test_commit_requires_root_build_and_terminal_children_before_storage", async () => {
  const store = await test_storage();
  const f = test_hooks(store.storage);
  const { project: _, ...args } = store.input;
  await expect(
    f.hooks.tool!.memory_commit.execute(args, test_context("coder", "child")),
  ).rejects.toThrow("root build");
  f.setChildren(true);
  await expect(
    f.hooks.tool!.memory_commit.execute(args, test_context()),
  ).rejects.toThrow("still active");
  expect(f.calls).toEqual([]);
  f.setChildren(false);
  expect(
    JSON.parse(
      (await f.hooks.tool!.memory_commit.execute(
        args,
        test_context(),
      )) as string,
    ).created,
  ).toBe(true);
  await expect(
    f.hooks.tool!.memory.execute(
      { mode: "profile", content: "Infer my preferences" },
      test_context(),
    ),
  ).rejects.toThrow("read-only");
  await expect(
    f.hooks.tool!.memory.execute(
      { mode: "add", content: "Bypass commit" },
      test_context(),
    ),
  ).rejects.toThrow("read-only");
});

test("test_consolidation_lease_covers_embedding_and_releases_after_failed_write", async () => {
  const store = await test_storage();
  const f = test_hooks(store.storage);
  const { project: _, ...args } = store.input;
  store.storage.embed = async () => {
    expect(f.hasLease()).toBe(true);
    await expect(
      f.hooks.tool!.memory_commit.execute(args, test_context()),
    ).rejects.toThrow("already active");
    return new Float32Array([0.1, 0.2]);
  };
  store.setFailInsert(true);
  await expect(
    f.hooks.tool!.memory_commit.execute(args, test_context()),
  ).rejects.toThrow("fixture insert failure");
  expect(f.hasLease()).toBe(false);
  store.setFailInsert(false);
  expect(
    JSON.parse(
      (await f.hooks.tool!.memory_commit.execute(
        args,
        test_context(),
      )) as string,
    ).created,
  ).toBe(true);
  expect(f.hasLease()).toBe(false);
});

test("test_wrong_baseline_version_is_rejected_before_plugin_execution", async () => {
  const root = await mkdtemp(join(tmpdir(), "opencode-memory-package-"));
  cleanups.push(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, "dist"));
  await writeFile(
    join(root, "package.json"),
    JSON.stringify({ name: "opencode-mem", version: "2.26.0" }),
  );
  await writeFile(
    join(root, "dist/plugin.js"),
    "throw new Error('must not execute');",
  );
  await expect(
    loadMemoryBaseline(join(root, "dist/plugin.js")),
  ).rejects.toThrow("requires opencode-mem 2.25.0");
});

test("test_pinned_storage_roundtrips_through_existing_memory_client_in_isolated_home", async () => {
  const root = await mkdtemp(join(tmpdir(), "opencode-memory-native-"));
  cleanups.push(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, ".config/opencode"), { recursive: true });
  await writeFile(
    join(root, ".config/opencode/opencode-mem.jsonc"),
    JSON.stringify({
      storagePath: join(root, "data"),
      embeddingModel: "fixture-only",
      embeddingDimensions: 2,
      autoCaptureEnabled: false,
      webServerEnabled: false,
    }),
  );
  const pinnedUrl = new URL(
    "../opencode/orchestrator/memory/pinned.ts",
    import.meta.url,
  ).href;
  const storeUrl = new URL(
    "../opencode/orchestrator/memory/store.ts",
    import.meta.url,
  ).href;
  const clientUrl = new URL(
    "../opencode/orchestrator/node_modules/opencode-mem/dist/services/client.js",
    import.meta.url,
  ).href;
  const closeUrl = new URL(
    "../opencode/orchestrator/node_modules/opencode-mem/dist/services/turso/lifecycle.js",
    import.meta.url,
  ).href;
  const script = join(root, "fixture.ts");
  await writeFile(
    script,
    `
    import { loadMemoryBaseline } from ${JSON.stringify(pinnedUrl)};
    import { commitMemoryOutcome } from ${JSON.stringify(storeUrl)};
    import { memoryClient } from ${JSON.stringify(clientUrl)};
    import { closeTursoAndInvalidateCaches } from ${JSON.stringify(closeUrl)};
    globalThis.fetch = async () => { throw new Error("Network access forbidden in memory fixture"); };
    const baseline = await loadMemoryBaseline();
    const storage = await baseline.storage(process.cwd());
    storage.embed = async () => new Float32Array([0.1, 0.2]);
    const input = { project: storage.project, workItem: "fixture-ticket", outcome: "done-v1", summary: "Verified fixture outcome", evidence: ["fixture.test.ts:1"] };
    const first = await commitMemoryOutcome(storage, input, "root-fixture");
    const second = await commitMemoryOutcome(storage, input, "root-fixture");
    const listed = await memoryClient.listMemories(storage.project, 10);
    if (!first.created || second.created || first.id !== second.id || listed.memories?.length !== 1 || listed.memories[0].id !== first.id) throw new Error("Pinned storage roundtrip failed");
    console.log(JSON.stringify({ count: listed.memories.length, sameID: first.id === second.id }));
    await closeTursoAndInvalidateCaches();
  `,
  );
  const child = Bun.spawnSync({
    cmd: [process.execPath, script],
    cwd: root,
    env: {
      HOME: root,
      PATH: process.env.PATH!,
      TMPDIR: root,
      GIT_CONFIG_NOSYSTEM: "1",
      GIT_CONFIG_GLOBAL: join(root, "no-git-config"),
    },
    stdout: "pipe",
    stderr: "pipe",
    timeout: 15000,
  });
  expect(child.stderr.toString()).toBe("");
  expect(child.exitCode).toBe(0);
  expect(child.stdout.toString().trim()).toBe(
    JSON.stringify({ count: 1, sameID: true }),
  );
});
