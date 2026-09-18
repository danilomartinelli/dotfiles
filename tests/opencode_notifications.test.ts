import { expect, test, spyOn } from "bun:test";
import { mkdtemp, realpath, rm, writeFile } from "node:fs/promises";
import os, { tmpdir } from "node:os";
import path from "node:path";
import { regularHooks } from "../opencode/orchestrator/regular";

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
            parentID: id === "root" ? undefined : "root",
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
    await run({
      hooks,
      directory,
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
  await fixture(async ({ hooks, directory, manager, request }: any) => {
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
    git("init");
    git("config", "core.excludesFile", "/dev/null");
    await writeFile(path.join(directory, ".gitignore"), ".local/\n");
    git("add", ".gitignore");
    git("commit", "-m", "Fixture");
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
