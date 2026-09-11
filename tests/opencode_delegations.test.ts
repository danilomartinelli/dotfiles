import { afterEach, expect, test } from "bun:test";
import {
  mkdtemp,
  rm,
  mkdir,
  writeFile,
  realpath,
  symlink,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  Delegations,
  sourceVersion,
  type Request,
} from "../opencode/orchestrator/delegations";
import { SessionJournals } from "../opencode/orchestrator/session-journals";
import { assertWriteTargets } from "../opencode/orchestrator/write-targets";

const cleanup: Array<() => Promise<void> | void> = [];
afterEach(async () => {
  for (const run of cleanup.splice(0).reverse()) await run();
});
const routes = {
  coder: { model: "openai/gpt-5.6-luna", variant: "high" },
  reviewer: { model: "openai/gpt-5.6-luna", variant: "high" },
  scribe: { model: "openai/gpt-5.6-luna", variant: "high" },
  explore: { model: "openai/gpt-5.6-luna", variant: "high" },
  researcher: { model: "openai/gpt-5.6-luna", variant: "high" },
};
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}
async function fixture(timeoutMs?: number) {
  const directory = await mkdtemp(
    path.join(tmpdir(), "orchestrator-delegations-"),
  );
  cleanup.push(() => rm(directory, { recursive: true, force: true }));
  const requests: any[] = [],
    created: any[] = [],
    aborts: string[] = [];
  const messages = new Map<string, any[]>();
  let snapshot = "source:1";
  const client = {
    session: {
      status: async () => ({ data: {} }),
      get: async ({ path: { id } }: any) => ({
        data: {
          id,
          directory,
          parentID: id.startsWith("child") ? "root" : undefined,
        },
      }),
      create: async (args: any) => {
        created.push(args);
        return { data: { id: `child-${created.length}` } };
      },
      promptAsync: async (args: any) => {
        requests.push(args);
        messages.set(args.path.id, [
          { info: { id: args.body.messageID, role: "user" }, parts: [] },
        ]);
        return {};
      },
      messages: async ({ path: { id } }: any) => ({
        data: messages.get(id) ?? [],
      }),
      abort: async ({ path: { id } }: any) => {
        aborts.push(id);
        return { data: true };
      },
    },
  };
  const filename = path.join(directory, "state.sqlite");
  const manager = new Delegations(
    filename,
    client as any,
    structuredClone(routes),
    timeoutMs,
    async () => snapshot,
  );
  cleanup.push(() => manager.close());
  const request = (overrides: Partial<Request> = {}): Request => ({
    role: "coder",
    workItem: "issue-1",
    directory,
    ownership: ["src"],
    prompt: "Implement bounded behavior; run focused checks.",
    ...overrides,
  });
  function result(child: string, text = "Verified result") {
    const entries = messages.get(child)!;
    entries.push({
      info: {
        id: `assistant-${entries.length}`,
        role: "assistant",
        parentID: entries[0].info.id,
        finish: "stop",
        time: { completed: Date.now() },
      },
      parts: [{ type: "text", text }],
    });
  }
  return {
    directory,
    filename,
    manager,
    client,
    request,
    requests,
    created,
    aborts,
    messages,
    result,
    setSnapshot: (value: string) => {
      snapshot = value;
    },
  };
}

test("invalid roles and leaf recursion create no child", async () => {
  const f = await fixture();
  await expect(
    f.manager.start("root", f.request({ role: "general" })),
  ).rejects.toThrow("Unknown delegation role");
  await expect(f.manager.start("child-99", f.request())).rejects.toThrow(
    "Leaf sessions",
  );
  expect(f.created).toHaveLength(0);
});

test("cross-project hooks recover the root journal, retain reservations on cancel and resume the same child", async () => {
  const f = await fixture();
  const target = path.join(await realpath(f.directory), "other-project");
  await mkdir(target);
  const sessions: Record<string, any> = {
    root: { id: "root", projectID: "root-project", directory: f.directory },
    "child-1": {
      id: "child-1",
      parentID: "root",
      projectID: "target-project",
      directory: target,
    },
    unregistered: {
      id: "unregistered",
      parentID: "root",
      projectID: "target-project",
      directory: target,
    },
    grandchild: {
      id: "grandchild",
      parentID: "child-1",
      projectID: "target-project",
      directory: target,
    },
  };
  f.client.session.get = async ({ path: { id } }: any) => ({
    data: sessions[id],
  });
  const journalDirectory = path.join(f.directory, "journals");
  function instance() {
    const journals = new SessionJournals(
      journalDirectory,
      f.client as any,
      routes,
    );
    cleanup.push(() => journals.close());
    return journals;
  }
  const rootInstance = instance();
  const manager = await rootInstance.forSession("root");
  const request = f.request({
    role: "scribe",
    directory: target,
    ownership: ["docs"],
  });
  const row = await manager.start("root", request);
  manager.savePlan("root", "Keep the same documentation scope.");
  const childInstance = instance();
  expect(
    (await childInstance.project("target-project")).forChild(row.child!),
  ).toBeUndefined();
  const childManager = await childInstance.forSession(row.child!);
  expect(childManager.readPlan("root")).toBe(
    "Keep the same documentation scope.",
  );
  expect(childManager.forChild(row.child!)?.ownership).toEqual([
    path.join(target, "docs"),
  ]);
  childManager.toolStarted(row.child!, "write-docs");
  expect((await manager.stop("root", row.id)).status).toBe("stopping");
  await expect(manager.start("root", request)).rejects.toThrow("overlaps");
  await childManager.toolFinished(row.child!, "write-docs");
  expect(manager.get("root", row.id).status).toBe("cancelled");
  const resumed = await manager.start("root", { ...request, resume: row.id });
  expect(resumed.child).toBe(row.child);
  expect(f.created).toHaveLength(1);
  f.result(row.child!);
  await childManager.complete(row.child!);
  expect(manager.get("root", row.id).status).toBe("completed");
  expect(manager.notifications("root")).toHaveLength(1);
  expect(childManager.notifications("root")).toEqual([]);
  await childInstance.close();
  const recovered = await instance().forSession(row.child!);
  expect(recovered.forChild(row.child!)?.result).toBe("Verified result");
  expect(recovered.get("root", row.id).notified).toBe(true);
  await expect(rootInstance.forSession("unregistered")).rejects.toThrow(
    "no matching root delegation",
  );
  await expect(rootInstance.forSession("grandchild")).rejects.toThrow(
    "Leaf sessions",
  );
  sessions["child-1"] = { ...sessions["child-1"], directory: f.directory };
  await expect(instance().forSession(row.child!)).rejects.toThrow(
    "no matching root delegation",
  );
  expect(f.created).toHaveLength(1);
});

test("support roles retain bounded delegation and their read or write capability", async () => {
  const f = await fixture();
  for (const role of ["explore", "researcher"]) {
    await expect(f.manager.start("root", f.request({ role }))).rejects.toThrow(
      "Read-only",
    );
    const row = await f.manager.start(
      "root",
      f.request({ role, ownership: [] }),
    );
    expect(row.route).toEqual({
      model: "openai/gpt-5.6-luna",
      variant: "high",
    });
    expect(row.sourceVersion).toBeUndefined();
  }
  await expect(
    f.manager.start("root", f.request({ role: "scribe", ownership: [] })),
  ).rejects.toThrow("explicit file");
  const scribe = await f.manager.start(
    "root",
    f.request({ role: "scribe", ownership: ["docs"] }),
  );
  expect(scribe.route.variant).toBe("high");
  await expect(
    f.manager.start("another-root", f.request({ ownership: ["docs/a.md"] })),
  ).rejects.toThrow("overlaps");
  expect(f.created).toHaveLength(3);
});

test("bounded parallel roles use explicit routes without metadata sessions", async () => {
  const f = await fixture();
  await Promise.all(
    ["a", "b", "c"].map((workItem) =>
      f.manager.start(
        "root",
        f.request({
          role: "reviewer",
          workItem,
          ownership: [],
          sourceVersion: "source:1",
        }),
      ),
    ),
  );
  await expect(
    f.manager.start(
      "root",
      f.request({
        role: "reviewer",
        workItem: "d",
        ownership: [],
        sourceVersion: "source:1",
      }),
    ),
  ).rejects.toThrow("Three delegations");
  expect(f.created).toHaveLength(3);
  expect(
    f.requests.every(
      (request) =>
        request.body.model.modelID === "gpt-5.6-luna" &&
        request.body.variant === "high",
    ),
  ).toBe(true);
  expect(
    f.created.every((request) => !request.body.title.includes("Metadata")),
  ).toBe(true);
});

test("writers across roots cannot overlap or run while the same worktree is reviewed", async () => {
  const f = await fixture();
  const row = await f.manager.start("root", f.request());
  await expect(
    f.manager.start("another-root", f.request({ ownership: ["src/one.ts"] })),
  ).rejects.toThrow("overlaps");
  await expect(
    f.manager.start(
      "another-root",
      f.request({ role: "reviewer", ownership: [], sourceVersion: "source:1" }),
    ),
  ).rejects.toThrow("writers finish");
  await f.manager.stop("root", row.id);
  await f.manager.start(
    "another-root",
    f.request({ role: "reviewer", ownership: [], sourceVersion: "source:1" }),
  );
  await expect(f.manager.start("root", f.request())).rejects.toThrow(
    "writers finish",
  );
});

test("same-work-item resume retains child and route but ignores the previous result", async () => {
  const f = await fixture();
  const first = await f.manager.start("root", f.request());
  f.result(first.child!);
  await f.manager.complete(first.child!);
  const old = f.messages.get(first.child!)!;
  const resumed = await f.manager.start(
    "root",
    f.request({ resume: first.id }),
  );
  f.messages.set(first.child!, old);
  await f.manager.complete(first.child!);
  expect(f.manager.get("root", resumed.id).status).toBe("running");
  expect(f.created).toHaveLength(1);
  expect(resumed.messageID).not.toBe(first.messageID);
  expect(f.requests.at(-1).body.variant).toBe("high");
  await f.manager.stop("root", resumed.id);
  await expect(
    f.manager.start("root", f.request({ resume: first.id, workItem: "other" })),
  ).rejects.toThrow("same work item");
});

test("compaction continuation can finish the current generation", async () => {
  const f = await fixture();
  const row = await f.manager.start("root", f.request());
  f.messages
    .get(row.child!)!
    .push({ info: { id: "continuation", role: "user" }, parts: [] });
  f.result(row.child!);
  f.messages.get(row.child!)!.at(-1).info.parentID = "continuation";
  await f.manager.complete(row.child!);
  expect(f.manager.get("root", row.id).status).toBe("completed");
});

test("completed tool-call steps retain their execution reservation", async () => {
  const f = await fixture();
  const row = await f.manager.start("root", f.request());
  f.result(row.child!);
  f.messages.get(row.child!)!.at(-1).info.finish = "tool-calls";
  await f.manager.recover("root");
  expect(f.manager.get("root", row.id).status).toBe("running");
  await expect(f.manager.start("root", f.request())).rejects.toThrow(
    "overlaps",
  );
});

test("deadline aborts execution without deleting or restarting the child", async () => {
  const f = await fixture(15);
  const row = await f.manager.start("root", f.request());
  await new Promise((done) => setTimeout(done, 35));
  expect(f.manager.get("root", row.id).status).toBe("timed_out");
  expect(f.aborts).toEqual([row.child!]);
  expect(f.created).toHaveLength(1);
});

test("deadline reconciles rejected tools and notifies the root without another user message", async () => {
  const f = await fixture(30);
  const notifications: string[] = [];
  f.manager.onStopped = async (row) => {
    notifications.push(row.status);
  };
  const row = await f.manager.start("root", f.request());
  f.manager.toolStarted(row.child!, "rejected-patch");
  f.messages.get(row.child!)!.push({
    info: { id: "tool-step", role: "assistant" },
    parts: [
      {
        type: "tool",
        callID: "rejected-patch",
        tool: "apply_patch",
        state: {
          status: "error",
          error: "Patch verification failed",
          time: { end: Date.now() },
        },
      },
    ],
  });
  await new Promise((done) => setTimeout(done, 65));
  await f.manager.complete(row.child!); // Native idle event following abort.
  expect(f.manager.get("root", row.id).status).toBe("timed_out");
  expect(notifications).toEqual(["timed_out"]);
  expect(f.aborts).toEqual([row.child!]);
  expect(f.created).toHaveLength(1);
});

test("cancellation during creation aborts the child before prompting", async () => {
  const f = await fixture();
  const gate = deferred<any>();
  f.client.session.create = async () => gate.promise;
  const pending = f.manager.start("root", f.request());
  while (!f.manager.list("root").length)
    await new Promise((done) => setTimeout(done, 1));
  const id = f.manager.list("root")[0].id;
  await f.manager.stop("root", id);
  gate.resolve({ data: { id: "child-delayed" } });
  await pending;
  expect(f.requests).toHaveLength(0);
  expect(f.aborts).toEqual(["child-delayed"]);
  expect(f.manager.get("root", id).status).toBe("cancelled");
});

test("late idle results cannot undo an acknowledged abort", async () => {
  const f = await fixture();
  const row = await f.manager.start("root", f.request());
  f.result(row.child!);
  const gate = deferred<any>();
  f.client.session.messages = async () => gate.promise;
  const pending = f.manager.complete(row.child!);
  await f.manager.stop("root", row.id);
  gate.resolve({ data: f.messages.get(row.child!) });
  await pending;
  expect(f.manager.get("root", row.id).status).toBe("cancelled");
});

test("failed abort keeps ownership reserved and never deletes or restarts a session", async () => {
  const f = await fixture();
  const row = await f.manager.start("root", f.request());
  f.client.session.abort = async () => ({ data: false });
  await f.manager.stop("root", row.id);
  expect(f.manager.get("root", row.id).status).toBe("stopping");
  await expect(f.manager.start("root", f.request())).rejects.toThrow(
    "overlaps",
  );
  expect(f.created).toHaveLength(1);
});

test("abort and idle do not release ownership before native tool cleanup acknowledges", async () => {
  const f = await fixture();
  const row = await f.manager.start("root", f.request());
  f.manager.toolStarted(row.child!, "shell-call");
  await f.manager.stop("root", row.id);
  expect(f.manager.get("root", row.id).status).toBe("stopping");
  expect(() => f.manager.toolStarted(row.child!, "late-spawn")).toThrow(
    "stopping",
  );
  await expect(f.manager.start("root", f.request())).rejects.toThrow(
    "overlaps",
  );
  await f.manager.toolFinished(row.child!, "shell-call");
  expect(f.manager.get("root", row.id).status).toBe("cancelled");
  await f.manager.start("root", f.request({ resume: row.id }));
  expect(f.created).toHaveLength(1);
});

test("changed review source invalidates its verdict", async () => {
  const f = await fixture();
  const row = await f.manager.start(
    "root",
    f.request({ role: "reviewer", ownership: [], sourceVersion: "source:1" }),
  );
  f.result(row.child!, "Approved");
  f.setSnapshot("source:2");
  await f.manager.complete(row.child!);
  expect(f.manager.get("root", row.id).status).toBe("failed");
  expect(f.manager.get("root", row.id).result).toContain("stale");
});

test("reopened state recovers results without creating new sessions", async () => {
  const f = await fixture();
  const row = await f.manager.start("root", f.request());
  f.result(row.child!);
  const recovered = new Delegations(f.filename, f.client as any, routes);
  try {
    await recovered.recover("root");
    expect(recovered.get("root", row.id).status).toBe("completed");
    expect(recovered.notifications("root")).toHaveLength(1);
    expect(recovered.notifications("root")).toHaveLength(0);
    expect(f.created).toHaveLength(1);
  } finally {
    recovered.close();
  }
});

test("memory consolidation excludes new work and releases its reservation after failure", async () => {
  const f = await fixture();
  const gate = deferred<void>();
  const capture = f.manager
    .consolidate("root", async () => {
      await gate.promise;
      throw new Error("storage failure");
    })
    .catch((error) => error);
  await expect(f.manager.start("root", f.request())).rejects.toThrow(
    "consolidation",
  );
  gate.resolve();
  expect(String(await capture)).toContain("storage failure");
  await f.manager.start("root", f.request());
  expect(f.created).toHaveLength(1);
});

async function gitFixture() {
  const f = await fixture();
  const git = (...args: string[]) => {
    const result = Bun.spawnSync(["git", ...args], {
      cwd: f.directory,
      env: {
        ...process.env,
        GIT_CONFIG_GLOBAL: "/dev/null",
        GIT_CONFIG_NOSYSTEM: "1",
        GIT_AUTHOR_NAME: "Fixture",
        GIT_AUTHOR_EMAIL: "fixture@example.invalid",
        GIT_COMMITTER_NAME: "Fixture",
        GIT_COMMITTER_EMAIL: "fixture@example.invalid",
      },
    });
    expect(result.exitCode).toBe(0);
    return result.stdout.toString().trim();
  };
  git("init");
  git("config", "core.excludesFile", "/dev/null");
  await writeFile(path.join(f.directory, ".gitignore"), "state.sqlite*\n");
  await writeFile(path.join(f.directory, "tracked"), "one");
  git("add", ".");
  git("commit", "-m", "Fixture");
  return { ...f, git };
}

test("snapshot includes staged, unstaged and untracked content", async () => {
  const f = await gitFixture();
  const one = await sourceVersion(f.directory);
  await writeFile(path.join(f.directory, "tracked"), "two");
  const two = await sourceVersion(f.directory);
  expect(two).not.toBe(one);
  f.git("add", "tracked");
  expect(await sourceVersion(f.directory)).toBe(two);
  await writeFile(path.join(f.directory, "new"), "three");
  expect(await sourceVersion(f.directory)).not.toBe(two);
});

test("coder artifacts survive resume without counting toward source snapshots", async () => {
  const f = await gitFixture();
  const row = await f.manager.start("root", f.request());
  expect(row.artifacts).toBeString();
  expect(row.ownership).toContain(row.artifacts!);
  expect(f.requests[0].body.parts[0].text).toContain(row.artifacts!);
  const baseline = await sourceVersion(f.directory);
  await Promise.all(
    Array.from({ length: 1001 }, (_, index) =>
      writeFile(path.join(row.artifacts!, `${index}.log`), "diagnostic\n"),
    ),
  );
  await writeFile(
    path.join(row.artifacts!, "large.bin"),
    new Uint8Array(17 * 1024 * 1024),
  );
  expect(await sourceVersion(f.directory)).toBe(baseline);
  await assertWriteTargets(
    "write",
    { filePath: path.join(row.artifacts!, "result.txt") },
    row,
  );
  await writeFile(
    path.join(f.directory, "new-source.ts"),
    "export const value = 1;\n",
  );
  expect(await sourceVersion(f.directory)).not.toBe(baseline);
  const sibling = await f.manager.start(
    "root",
    f.request({ ownership: ["other-src"], workItem: "other" }),
  );
  expect(sibling.artifacts).not.toBe(row.artifacts);
  await expect(
    assertWriteTargets(
      "write",
      { filePath: path.join(row.artifacts!, "result.txt") },
      sibling,
    ),
  ).rejects.toThrow("outside delegated");
  f.result(row.child!);
  await f.manager.complete(row.child!);
  const resumed = await f.manager.start("root", f.request({ resume: row.id }));
  expect(resumed.artifacts).toBe(row.artifacts);
  expect(await Bun.file(path.join(row.artifacts!, "1000.log")).text()).toBe(
    "diagnostic\n",
  );
  expect(await Bun.file(path.join(f.directory, ".gitignore")).text()).toBe(
    "state.sqlite*\n",
  );
});

test("artifact preparation rejects symlinks without claiming external paths or starting a child", async () => {
  const f = await gitFixture();
  const external = await mkdtemp(
    path.join(tmpdir(), "external-artifact-fixture-"),
  );
  cleanup.push(() => rm(external, { recursive: true, force: true }));
  await symlink(external, path.join(f.directory, ".opencode-artifacts"));
  await expect(f.manager.start("root", f.request())).rejects.toThrow(
    "real directory",
  );
  expect(f.created).toHaveLength(0);
  expect(await Bun.file(path.join(external, ".gitignore")).exists()).toBe(
    false,
  );
});

test("snapshot limits explain counts, bytes and responsible paths while preserving evidence", async () => {
  const f = await gitFixture();
  await mkdir(path.join(f.directory, ".tmp"));
  await Promise.all(
    Array.from({ length: 1001 }, (_, index) =>
      writeFile(path.join(f.directory, ".tmp", `${index}.log`), "diagnostic\n"),
    ),
  );
  await expect(sourceVersion(f.directory)).rejects.toThrow(
    "1001 untracked files",
  );
  await expect(sourceVersion(f.directory)).rejects.toThrow('".tmp/"');
  await expect(sourceVersion(f.directory)).rejects.toThrow("Preserve evidence");
  expect(await Bun.file(path.join(f.directory, ".tmp/1000.log")).text()).toBe(
    "diagnostic\n",
  );
  const large = await gitFixture();
  await writeFile(
    path.join(large.directory, "capture.bin"),
    new Uint8Array(17 * 1024 * 1024),
  );
  await expect(sourceVersion(large.directory)).rejects.toThrow("17.00 MiB");
  await expect(sourceVersion(large.directory)).rejects.toThrow("capture.bin");
});

test("recursive directory ownership permits intended writes and reserves the whole directory", async () => {
  const f = await fixture();
  const row = await f.manager.start(
    "root",
    f.request({ ownership: ["src/**"] }),
  );
  expect(row.ownership).toContain(
    path.join(await realpath(f.directory), "src"),
  );
  await assertWriteTargets("write", { filePath: "src/nested/file.ts" }, row);
  await expect(
    f.manager.start("other-root", f.request({ ownership: ["src/nested"] })),
  ).rejects.toThrow("overlaps");
  await expect(
    f.manager.start("root", f.request({ ownership: ["lib/*.ts"] })),
  ).rejects.toThrow("literal paths");
});

test("review preparation waits for writers in that checkout and identifies their reservations", async () => {
  const f = await fixture();
  await f.manager.start("root", f.request({ role: "explore", ownership: [] }));
  expect(() => f.manager.assertReviewReady(f.directory)).not.toThrow();
  const writer = await f.manager.start("root", f.request());
  expect(() => f.manager.assertReviewReady(writer.directory)).toThrow(
    writer.id,
  );
  expect(() =>
    f.manager.assertReviewReady(path.join(writer.directory, "nested")),
  ).toThrow("writers finish");
  expect(() =>
    f.manager.assertReviewReady(`${writer.directory}-other`),
  ).not.toThrow();
  await f.manager.stop("root", writer.id);
  expect(() => f.manager.assertReviewReady(writer.directory)).not.toThrow();
  expect(() => f.manager.assertSettled("root")).toThrow("active delegations");
});

test("resume errors distinguish active execution, mismatched identity and profile changes", async () => {
  const f = await fixture();
  const row = await f.manager.start("root", f.request());
  await expect(
    f.manager.start("root", f.request({ resume: row.id })),
  ).rejects.toThrow("confirmed terminal status");
  f.result(row.child!);
  await f.manager.complete(row.child!);
  await expect(
    f.manager.start(
      "root",
      f.request({ resume: row.id, workItem: "different" }),
    ),
  ).rejects.toThrow("recorded fields exactly");
  const updated = new Delegations(f.filename, f.client as any, {
    ...routes,
    coder: { ...routes.coder, variant: "medium" },
  });
  try {
    await expect(
      updated.start("root", f.request({ resume: row.id })),
    ).rejects.toThrow("profile route changed");
    expect(f.created).toHaveLength(1);
  } finally {
    updated.close();
  }
});

test("artifact storage preserves unrelated source and refuses tracked artifacts or a replaced marker", async () => {
  const f = await gitFixture();
  await mkdir(path.join(f.directory, ".opencode-artifacts"));
  await writeFile(
    path.join(f.directory, ".opencode-artifacts", "user-source.ts"),
    "source\n",
  );
  const row = await f.manager.start("root", f.request());
  expect(f.git("ls-files", "--others", "--exclude-standard")).toContain(
    "user-source.ts",
  );
  f.result(row.child!);
  await f.manager.complete(row.child!);
  await writeFile(path.join(row.artifacts!, "proof.txt"), "keep\n");
  f.git("add", "-f", path.join(row.artifacts!, "proof.txt"));
  await expect(
    f.manager.start("root", f.request({ resume: row.id })),
  ).rejects.toThrow("tracked files");
  expect(await Bun.file(path.join(row.artifacts!, "proof.txt")).text()).toBe(
    "keep\n",
  );
  const other = await gitFixture();
  const second = await other.manager.start("root", other.request());
  other.result(second.child!);
  await other.manager.complete(second.child!);
  await writeFile(path.join(second.artifacts!, ".gitignore"), "custom rule\n");
  await expect(
    other.manager.start("root", other.request({ resume: second.id })),
  ).rejects.toThrow("managed marker");
  expect(
    await Bun.file(path.join(second.artifacts!, ".gitignore")).text(),
  ).toBe("custom rule\n");
});
