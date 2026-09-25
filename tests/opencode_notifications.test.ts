import { expect, test, spyOn } from "bun:test";
import { mkdtemp, realpath, rm, writeFile } from "node:fs/promises";
import os, { tmpdir } from "node:os";
import path from "node:path";
import { regularHooks } from "../opencode/orchestrator/regular";
import { CodeGraphProjects } from "../opencode/orchestrator/codegraph";
import { rolePermissions } from "../opencode/orchestrator/prompts";

// The agreed classification, written out here rather than read back from the
// policy module, so an answer both adapters share can still be wrong and fail.
const rootTools = [
  "compress",
  "delegate",
  "delegation_list",
  "delegation_cancel",
  "review_snapshot",
  "plan_save",
  "memory_commit",
  "todowrite",
  "question",
  "worktree_create",
  "worktree_delete",
];
const sharedTools = ["delegation_read", "plan_read", "todoread", "memory"];

/** OpenCode applies the last native permission rule whose pattern matches. */
function nativeAnswer(permissions: Record<string, unknown>, tool: string) {
  let answer: unknown;
  for (const [pattern, value] of Object.entries(permissions)) {
    const glob = pattern
      .split("*")
      .map((part) => part.replace(/[.+?^${}()|[\]\\]/g, "\\$&"))
      .join(".*");
    if (new RegExp(`^${glob}$`).test(tool)) answer = value;
  }
  return answer;
}

/** Moves a recorded deadline into the past, as if the process had been away. */
async function expire(home: string, id: string) {
  const { Database } = await import("bun:sqlite");
  const db = new Database(
    path.join(home, ".local/share/opencode/orchestrator/fixture.sqlite"),
  );
  try {
    const stored = db
      .query("SELECT record FROM delegations WHERE id=?")
      .get(id) as { record: string };
    const record = JSON.parse(stored.record);
    record.deadline = Date.now() - 1;
    db.query("UPDATE delegations SET record=? WHERE id=?").run(
      JSON.stringify(record),
      id,
    );
  } finally {
    db.close();
  }
}

function finish(messages: Map<string, any[]>, child: string, text: string) {
  messages.get(child)!.push({
    info: { role: "assistant", finish: "stop", time: { completed: Date.now() } },
    parts: [{ type: "text", text }],
  });
}

async function fixture(run: (f: any) => Promise<void>) {
  const directory = await realpath(
    await mkdtemp(path.join(tmpdir(), "opencode-notifications-")),
  );
  const home = spyOn(os, "homedir").mockReturnValue(directory);
  const previousProfile = process.env.DOTFILES_OPENCODE_PROFILE_CONFIG;
  delete process.env.DOTFILES_OPENCODE_PROFILE_CONFIG;
  let hooks: any;
  try {
    const messages = new Map<string, any[]>();
    messages.set("root", [
      { info: { role: "assistant", agent: "build" }, parts: [] },
    ]);
    const requests: any[] = [];
    let created = 0;
    const client = {
      session: {
        get: async ({ path: { id } }: any) => ({
          data: {
            id,
            directory,
            projectID: "fixture",
            // Sessions named like a root are roots; every other one is a child of root.
            parentID: /root$/.test(id) ? undefined : "root",
          },
        }),
        status: async () => ({ data: {} }),
        messages: async ({ path: { id } }: any) => ({
          data: messages.get(id) ?? [],
        }),
        create: async () => ({ data: { id: `child-${++created}` } }),
        abort: async () => ({ data: true }),
        promptAsync: async (args: any) => {
          requests.push(args);
          if (args.path.id !== "root")
            messages.set(args.path.id, [
              {
                info: { id: args.body.messageID, role: "user" },
                parts: [],
              },
            ]);
          return {};
        },
      },
    };
    const agent = Object.fromEntries(
      [
        "build",
        "plan",
        "coder",
        "reviewer",
        "scribe",
        "explore",
        "researcher",
      ].map((role) => [
        role,
        {
          model: ["build", "plan"].includes(role)
            ? "openai/gpt-6-astra"
            : "openai/gpt-5.6-luna",
          variant: ["build", "plan"].includes(role) ? "max" : "high",
        },
      ]),
    );
    const runtime = await regularHooks(
      { client, directory, worktree: directory } as any,
      { agent },
    );
    hooks = runtime.hooks;
    const manager = await runtime.managerFor("root");
    const git = (...args: string[]) => {
      const result = Bun.spawnSync(["git", ...args], {
        cwd: directory,
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
    };
    await run({
      hooks,
      directory,
      /** A committed checkout, which a reviewer's source version requires. */
      checkout: async () => {
        git("init");
        git("config", "core.excludesFile", "/dev/null");
        await writeFile(path.join(directory, ".gitignore"), ".local/\n");
        git("add", ".gitignore");
        git("commit", "-m", "Fixture");
      },
      manager,
      messages,
      requests,
      client,
      request: (workItem: string) => ({
        role: "coder",
        workItem,
        directory,
        ownership: [workItem],
        prompt: "Verify the bounded scope.",
      }),
      idle: (sessionID: string) =>
        hooks.event({
          event: { type: "session.idle", properties: { sessionID } },
        }),
    });
  } finally {
    await hooks?.dispose();
    home.mockRestore();
    if (previousProfile === undefined)
      delete process.env.DOTFILES_OPENCODE_PROFILE_CONFIG;
    else process.env.DOTFILES_OPENCODE_PROFILE_CONFIG = previousProfile;
    await rm(directory, { recursive: true, force: true });
  }
}

test("the review snapshot tool allows read-only children while enforcing writer reservations", async () => {
  await fixture(async ({ hooks, directory, manager, request, checkout }: any) => {
    await checkout();
    await manager.start("root", {
      ...request("investigate"),
      role: "explore",
      ownership: [],
    });
    const snapshot = () =>
      hooks.tool.review_snapshot.execute({ directory }, { sessionID: "root" });
    expect(await snapshot()).toMatch(/^[a-f0-9]+:[a-f0-9]+$/);
    const writer = await manager.start("root", request("implement"));
    await expect(snapshot()).rejects.toThrow(writer.id);
    await manager.stop("root", writer.id);
    expect(await snapshot()).toMatch(/^[a-f0-9]+:[a-f0-9]+$/);
  });
});

test("the review snapshot tool prepares CodeGraph only when enabled and review is allowed", () =>
  fixture(async ({ hooks, directory, manager, request, checkout }: any) => {
    await checkout();
    const prepared: string[] = [];
    const prepare = spyOn(
      CodeGraphProjects.prototype,
      "prepare",
    ).mockImplementation(async (target: string) => {
      prepared.push(target);
      return { ready: true, notice: "" };
    });
    try {
      const snapshot = () =>
        hooks.tool.review_snapshot.execute(
          { directory },
          { sessionID: "root" },
        );
      await hooks.config({ agent: {}, mcp: { codegraph: { enabled: false } } });
      expect(await snapshot()).toMatch(/^[a-f0-9]+:[a-f0-9]+$/);
      expect(prepared).toEqual([]);
      await hooks.config({ agent: {}, mcp: { codegraph: {} } });
      const writer = await manager.start("root", request("implement"));
      await expect(snapshot()).rejects.toThrow(writer.id);
      expect(prepared).toEqual([]);
      await manager.stop("root", writer.id);
      expect(await snapshot()).toMatch(/^[a-f0-9]+:[a-f0-9]+$/);
      expect(prepared).toEqual([directory]);
    } finally {
      prepare.mockRestore();
    }
  }));

test("regular tool admission preserves role gates, ordering, and query effects", () =>
  fixture(async ({ hooks, manager, request }: any) => {
    const before = (
      sessionID: string,
      tool: string,
      args: any,
      callID = `${sessionID}-${tool}`,
    ) =>
      hooks["tool.execute.before"](
        { sessionID, tool, callID },
        { args },
      );
    const after = (sessionID: string, callID: string) =>
      hooks["tool.execute.after"]({ sessionID, callID }, {});

    await expect(
      before("root", "task", {}),
    ).rejects.toThrow("native task routing is disabled");
    await expect(
      before("root", "memory", { mode: "search" }),
    ).resolves.toBeUndefined();
    await expect(
      before("root", "memory", { mode: "search", content: "write" }),
    ).rejects.toThrow("retrieval-only");

    const deniedWriter = await manager.start("root", request("owned-denied.txt"));
    await expect(
      before(deniedWriter.child, "memory_commit", {}),
    ).rejects.toThrow("Only the root orchestrator");
    await expect(
      before(
        deniedWriter.child,
        "write",
        { filePath: "outside.txt" },
        "denied-writer-write",
      ),
    ).rejects.toThrow("outside delegated file ownership");
    const stoppedDeniedWriter = await manager.stop("root", deniedWriter.id);
    expect(stoppedDeniedWriter.status).toBe("cancelled");

    const writer = await manager.start("root", request("owned-allowed.txt"));
    await expect(
      before(
        writer.child,
        "write",
        { filePath: "owned-allowed.txt" },
        "allowed-writer-write",
      ),
    ).resolves.toBeUndefined();
    const stoppingWriter = await manager.stop("root", writer.id);
    expect(stoppingWriter.status).toBe("stopping");
    await expect(after(writer.child, "allowed-writer-write")).resolves.toBeUndefined();
    expect(manager.get("root", writer.id).status).toBe("cancelled");

    await hooks.config({ agent: {}, mcp: { exa: {} }, permission: {} });
    const deniedReader = await manager.start("root", {
      ...request("read-only"),
      role: "explore",
      ownership: [],
    });
    await expect(
      before(deniedReader.child, "exa_agent_run", {}, "denied-reader-exa"),
    ).rejects.toThrow("cannot execute exa_agent_run");
    const stoppedDeniedReader = await manager.stop("root", deniedReader.id);
    expect(stoppedDeniedReader.status).toBe("cancelled");

    const reader = await manager.start("root", {
      ...request("read-only-allowed"),
    });
    await expect(
      before(reader.child, "exa_web_fetch_exa", {
        urls: ["https://example.invalid/docs"],
      }, "allowed-reader-exa"),
    ).resolves.toBeUndefined();
    const stoppingReader = await manager.stop("root", reader.id);
    expect(stoppingReader.status).toBe("stopping");
    await expect(after(reader.child, "allowed-reader-exa")).resolves.toBeUndefined();
    expect(manager.get("root", reader.id).status).toBe("cancelled");
  }));

test("orchestration and memory tools mean the same thing natively and at admission", () =>
  fixture(async ({ hooks, manager, request, messages, checkout, directory }: any) => {
    await checkout();
    messages.set("plan-root", [
      { info: { role: "assistant", agent: "plan" }, parts: [] },
    ]);
    const sessions: [string, string][] = [
      ["build", "root"],
      ["plan", "plan-root"],
    ];
    const children: Record<string, () => Promise<any>> = {
      coder: async () => request("coder-owned.txt"),
      scribe: async () => ({ ...request("scribe-owned.md"), role: "scribe" }),
      explore: async () => ({
        ...request("explore"),
        role: "explore",
        ownership: [],
      }),
      researcher: async () => ({
        ...request("research"),
        role: "researcher",
        ownership: [],
      }),
      reviewer: async () => ({
        ...request("review"),
        role: "reviewer",
        ownership: [],
        sourceVersion: await hooks.tool.review_snapshot.execute(
          { directory },
          { sessionID: "root" },
        ),
      }),
    };
    for (const [role, delegation] of Object.entries(children)) {
      const row = await manager.start("root", await delegation());
      await manager.stop("root", row.id);
      sessions.push([role, row.child]);
    }

    // worktree_list stands for any tool a plugin update adds under the prefix.
    for (const [role, sessionID] of sessions) {
      const permissions = rolePermissions(role);
      const root = role === "build" || role === "plan";
      for (const tool of [...rootTools, ...sharedTools, "task", "worktree_list"]) {
        const allowed =
          sharedTools.includes(tool) || (root && rootTools.includes(tool));
        const label = `${role} ${tool}`;
        expect(nativeAnswer(permissions, tool), label).toBe(
          allowed ? "allow" : "deny",
        );
        const admission = hooks["tool.execute.before"](
          { sessionID, tool, callID: `${sessionID}-${tool}` },
          { args: tool === "memory" ? { mode: "search" } : {} },
        );
        if (allowed) await expect(admission, label).resolves.toBeUndefined();
        else await expect(admission, label).rejects.toThrow();
      }
    }
  }));

test("delegation listing stays with the root at every entry point", () =>
  fixture(async ({ hooks, manager, request, messages }: any) => {
    const reader = await manager.start("root", {
      ...request("read-evidence"),
      role: "explore",
      ownership: [],
    });
    const writer = await manager.start("root", request("finished.txt"));
    const unrelated = await manager.start("another-root", {
      ...request("unrelated"),
      role: "explore",
      ownership: [],
    });
    messages.get(writer.child).push({
      info: {
        role: "assistant",
        finish: "stop",
        time: { completed: Date.now() },
      },
      parts: [{ type: "text", text: "Retained evidence." }],
    });

    expect(nativeAnswer(rolePermissions("explore"), "delegation_list")).toBe(
      "deny",
    );
    await expect(
      hooks["tool.execute.before"](
        { sessionID: reader.child, tool: "delegation_list", callID: "list" },
        { args: {} },
      ),
    ).rejects.toThrow("Only the root orchestrator");
    // A direct call skips the hook, and a claimed root agent is not identity.
    await expect(
      hooks.tool.delegation_list.execute({}, {
        sessionID: reader.child,
        agent: "build",
      }),
    ).rejects.toThrow("Leaf sessions");
    // Recovery would have settled the finished writer; the refusal came first.
    expect(manager.get("root", writer.id).status).toBe("running");

    const rows = JSON.parse(
      await hooks.tool.delegation_list.execute({}, {
        sessionID: "root",
        agent: "build",
      }),
    );
    expect(rows.map((row: any) => row.id).sort()).toEqual(
      [reader.id, writer.id].sort(),
    );
    expect(rows.every((row: any) => !Object.hasOwn(row, "result"))).toBe(true);
    expect(rows.find((row: any) => row.id === writer.id).status).toBe(
      "completed",
    );

    // Reading a known delegation of the same root stays available to a child.
    const retained = JSON.parse(
      await hooks.tool.delegation_read.execute(
        { id: writer.id },
        { sessionID: reader.child },
      ),
    );
    expect(retained.result).toBe("Retained evidence.");
    await expect(
      hooks.tool.delegation_read.execute(
        { id: unrelated.id },
        { sessionID: reader.child },
      ),
    ).rejects.toThrow("not found in this root");
  }));

test("memory admission accepts queries and refuses writes for every role", () =>
  fixture(async ({ hooks, manager, request }: any) => {
    const writer = await manager.start("root", request("memory-writer.txt"));
    for (const sessionID of ["root", writer.child]) {
      const admit = (args: Record<string, unknown>) =>
        hooks["tool.execute.before"](
          { sessionID, tool: "memory", callID: `${sessionID}-memory` },
          { args },
        );
      for (const mode of ["search", "list", "profile", "help"])
        await expect(admit({ mode, query: "auth" })).resolves.toBeUndefined();
      await expect(admit({})).resolves.toBeUndefined();
      for (const mode of ["add", "forget", "migrate", "export", "delete"])
        await expect(admit({ mode }), mode).rejects.toThrow("retrieval-only");
      await expect(
        admit({ mode: "search", content: "Store this" }),
      ).rejects.toThrow("retrieval-only");
      await expect(admit({ content: "Store this" })).rejects.toThrow(
        "retrieval-only",
      );
    }
  }));

test("identity and permission lookups leave expired work to prepared operations", () =>
  fixture(async ({ hooks, manager, request, requests, client, directory }: any) => {
    const reader = await manager.start("root", {
      ...request("lookup"),
      role: "explore",
      ownership: [],
    });
    const writer = await manager.start("root", request("expired.txt"));
    await expire(directory, writer.id);
    const aborts: string[] = [];
    const abort = client.session.abort;
    client.session.abort = async (args: any) => {
      aborts.push(args.path.id);
      return abort(args);
    };

    await hooks["tool.execute.before"](
      { sessionID: reader.child, tool: "todoread", callID: "todo" },
      { args: {} },
    );
    await hooks["chat.params"](
      {
        sessionID: reader.child,
        agent: "explore",
        model: { providerID: "openai", id: "gpt-5.6-luna" },
        message: {},
      },
      { options: {} },
    );
    expect(
      await hooks.tool.plan_read.execute({}, { sessionID: reader.child }),
    ).toBe("No plan saved for this session.");
    expect(manager.get("root", writer.id).status).toBe("running");
    expect(aborts).toEqual([]);
    expect(requests.filter((r: any) => r.path.id === "root")).toHaveLength(0);

    // Reading a record is a refreshed consultation, which applies the deadline.
    await hooks.tool.delegation_read.execute(
      { id: writer.id },
      { sessionID: reader.child },
    );
    expect(manager.get("root", writer.id).status).toBe("timed_out");
    expect(aborts).toEqual([writer.child]);
  }));

test("recovery delivers the stop it causes without recovering again", () =>
  fixture(async ({ hooks, manager, request, requests, client, directory }: any) => {
    const first = await manager.start("root", request("first.txt"));
    await expire(directory, first.id);
    const rows = JSON.parse(
      await hooks.tool.delegation_list.execute({}, {
        sessionID: "root",
        agent: "build",
      }),
    );
    expect(rows.map((row: any) => row.status)).toEqual(["timed_out"]);
    const wakes = () => requests.filter((r: any) => r.path.id === "root");
    expect(wakes()).toHaveLength(1);
    expect(wakes()[0].body.parts[0].text).toContain(
      `${first.id}: coder timed_out`,
    );

    // A failed delivery restores the notice for the next root message.
    const second = await manager.start("root", request("second.txt"));
    await expire(directory, second.id);
    const send = client.session.promptAsync;
    client.session.promptAsync = async (args: any) =>
      args.path.id === "root" ? { error: "unavailable" } : send(args);
    await hooks.tool.delegation_read.execute(
      { id: second.id },
      { sessionID: "root" },
    );
    expect(manager.get("root", second.id).status).toBe("timed_out");
    expect(manager.get("root", second.id).notified).toBe(false);
    client.session.promptAsync = send;
    const output = {
      message: { id: "msg-root" },
      parts: [{ type: "text", text: "Continue." }],
    };
    await hooks["chat.message"]({ sessionID: "root", agent: "build" }, output);
    expect(output.parts.at(-1)).toMatchObject({ synthetic: true });
    expect((output.parts.at(-1) as any).text).toContain(
      `${second.id}: coder timed_out`,
    );
    expect(manager.get("root", second.id).notified).toBe(true);
    expect(wakes()).toHaveLength(1);
  }));

test("root messages and compaction observe settled work without recreating children", () =>
  fixture(async ({ hooks, manager, request, messages, client }: any) => {
    let created = 0;
    const create = client.session.create;
    client.session.create = async (args: any) => {
      created++;
      return create(args);
    };
    const first = await manager.start("root", request("first.txt"));
    finish(messages, first.child, "First evidence.");
    const output = {
      message: { id: "msg-root" },
      parts: [{ type: "text", text: "Continue." }],
    };
    await hooks["chat.message"]({ sessionID: "root", agent: "build" }, output);
    expect((output.parts.at(-1) as any).text).toContain(
      `${first.id}: coder completed`,
    );

    const second = await manager.start("root", request("second.txt"));
    finish(messages, second.child, "Second evidence.");
    await hooks.tool.plan_save.execute(
      { content: "Keep both scopes." },
      { sessionID: "root" },
    );
    const compacted = { context: [] as string[] };
    await hooks["experimental.session.compacting"](
      { sessionID: "root" },
      compacted,
    );
    const [heading, plan, json, guidance] = compacted.context[1].split("\n");
    expect([heading, plan]).toEqual(["Orchestration recovery:", "Keep both scopes."]);
    const records = JSON.parse(json);
    expect(records.map((row: any) => [row.id, row.status])).toEqual([
      [first.id, "completed"],
      [second.id, "completed"],
    ]);
    expect(records.every((row: any) => !Object.hasOwn(row, "result"))).toBe(
      true,
    );
    expect(guidance).toContain("Do not recreate children after compaction.");
    expect(created).toBe(2);
  }));

test("a pending stop wakes the existing root once and preserves ownership until acknowledgement", () =>
  fixture(async (f) => {
    const row = await f.manager.start("root", f.request("first"));
    const sibling = await f.manager.start("root", f.request("second"));
    f.manager.toolStarted(row.child, "pending-operation");
    await f.manager.stop(
      "root",
      row.id,
      "timed_out",
      "Delegation exceeded its deadline.",
    );
    await f.idle(row.child);
    const notices = () => f.requests.filter((r: any) => r.path.id === "root");
    expect(notices()).toHaveLength(1);
    expect(notices()[0].body.parts[0].text).toContain("stopping");
    expect(notices()[0].body.model).toEqual({
      providerID: "openai",
      modelID: "gpt-6-astra",
    });
    expect(notices()[0].body.variant).toBe("max");
    expect(f.manager.get("root", sibling.id).status).toBe("running");
    await expect(
      f.manager.start("root", { ...f.request("first"), resume: row.id }),
    ).rejects.toThrow("terminal");
    await f.manager.toolFinished(row.child, "pending-operation");
    expect(notices()).toHaveLength(2);
    expect(notices()[1].body.parts[0].text).toContain("timed_out");
    await f.idle(row.child);
    expect(notices()).toHaveLength(2);
    const resumed = await f.manager.start("root", {
      ...f.request("first"),
      resume: row.id,
    });
    expect(resumed.child).toBe(row.child);
  }));

test("a failed child wakes the root while successful siblings remain batched", () =>
  fixture(async (f) => {
    const first = await f.manager.start("root", f.request("first"));
    const second = await f.manager.start("root", f.request("second"));
    const successful = await f.manager.start("root", f.request("third"));
    f.messages.get(successful.child).push({
      info: {
        role: "assistant",
        finish: "stop",
        time: { completed: Date.now() },
      },
      parts: [{ type: "text", text: "Verified scope." }],
    });
    await f.idle(successful.child);
    expect(f.requests.filter((r: any) => r.path.id === "root")).toHaveLength(0);
    f.messages.get(first.child).push({
      info: {
        role: "assistant",
        time: { completed: Date.now() },
        error: { name: "ProviderError" },
      },
      parts: [],
    });
    await f.idle(first.child);
    expect(f.requests.filter((r: any) => r.path.id === "root")).toHaveLength(1);
    expect(f.manager.get("root", second.id).status).toBe("running");
    await f.idle(first.child);
    expect(f.requests.filter((r: any) => r.path.id === "root")).toHaveLength(1);
    expect(f.manager.get("root", successful.id).notified).toBe(false);
    f.messages.get(second.child).push({
      info: {
        role: "assistant",
        finish: "stop",
        time: { completed: Date.now() },
      },
      parts: [{ type: "text", text: "Verified remaining scope." }],
    });
    await f.idle(second.child);
    expect(f.requests.filter((r: any) => r.path.id === "root")).toHaveLength(2);
    expect(f.manager.get("root", successful.id).notified).toBe(true);
  }));

test("a delivery failure retains its notice without rearming a resumed generation", () =>
  fixture(async (f) => {
    const first = await f.manager.start("root", f.request("first"));
    const send = f.client.session.promptAsync;
    f.client.session.promptAsync = async () => {
      throw new Error("Temporary transport failure");
    };
    await f.manager.stop("root", first.id, "timed_out");
    expect(f.manager.get("root", first.id).notified).toBe(false);
    const oldNotices = f.manager.notifications("root");
    f.manager.restoreNotifications("root", oldNotices);
    f.client.session.promptAsync = send;
    await f.idle(first.child);
    expect(f.requests.filter((r: any) => r.path.id === "root")).toHaveLength(1);
    expect(f.manager.get("root", first.id).notified).toBe(true);
    const resumed = await f.manager.start("root", {
      ...f.request("first"),
      resume: first.id,
    });
    await f.manager.stop("root", resumed.id, "timed_out");
    f.manager.restoreNotifications("root", oldNotices);
    expect(f.manager.get("root", first.id).notified).toBe(true);
  }));
