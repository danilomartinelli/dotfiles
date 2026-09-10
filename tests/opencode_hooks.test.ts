import { expect, test } from "bun:test";
import {
  combineHooks,
  initializeFromConfig,
} from "../opencode/orchestrator/hooks";

test("orchestration and memory hooks preserve ordering while duplicate tools fail before activation", async () => {
  const calls: string[] = [];
  const plugin = combineHooks(
    {
      event: async () => {
        calls.push("orchestration");
      },
    },
    {
      event: async () => {
        calls.push("retrieval");
      },
    },
    {
      event: async () => {
        calls.push("memory");
      },
    },
  );
  await plugin.event!({
    event: { type: "session.idle", properties: { sessionID: "fixture" } },
  });
  expect(calls).toEqual(["orchestration", "retrieval", "memory"]);
  const tool = {
    description: "fixture",
    args: {},
    execute: async () => "fixture",
  };
  expect(() =>
    combineHooks({ tool: { delegate: tool } }, { tool: { delegate: tool } }),
  ).toThrow("Duplicate plugin tool");
});

test("configuration initializes hooks without a recursive client request and tolerates absent optional hooks", async () => {
  let initialized = 0;
  const plugin = initializeFromConfig(async (config) => {
    expect(config.agent?.["coder"]).toBeDefined();
    initialized++;
    return combineHooks({
      dispose: undefined,
      tool: {
        fixture: {
          description: "fixture",
          args: {},
          execute: async () => "ready",
        },
      },
    });
  });
  await plugin.config!({ agent: { coder: {} } });
  expect(initialized).toBe(1);
  expect(Object.keys(plugin.tool!)).toEqual(["fixture"]);
  await plugin.dispose!();
});

test("failed initialization keeps execution hooks closed even if the host ignores the config error", async () => {
  const plugin = initializeFromConfig(async () => {
    throw new Error("broken integration");
  });
  await expect(plugin.config!({})).rejects.toThrow("broken integration");
  await expect(
    plugin["tool.execute.before"]!(
      { tool: "bash", sessionID: "root", callID: "call" },
      { args: { command: "echo unsafe" } },
    ),
  ).rejects.toThrow("broken integration");
});
