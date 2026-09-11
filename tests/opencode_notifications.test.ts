import { expect, test, spyOn } from "bun:test";
import { mkdtemp, realpath, rm } from "node:fs/promises";
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
          model: `openai/gpt-5.6-${["build", "plan"].includes(role) ? "sol" : "luna"}`,
          variant: ["build", "plan"].includes(role) ? "xhigh" : "high",
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
      modelID: "gpt-5.6-sol",
    });
    expect(notices()[0].body.variant).toBe("xhigh");
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
