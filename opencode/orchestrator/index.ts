import type { Plugin } from "@opencode-ai/plugin";
import { existsSync } from "node:fs";
import path from "node:path";
import os from "node:os";
import { combineHooks, initializeFromConfig } from "./hooks";
import { createRegularMemoryHooks, loadMemoryBaseline } from "./memory";
import { regularHooks } from "./regular";

const Orchestrator: Plugin = async (ctx) => {
  return initializeFromConfig(async (effective) => {
    // Never combine the old auto-loaded workflow hooks with this replacement.
    for (const name of ["background-agents.ts", "workspace-plugin.ts"]) {
      if (
        existsSync(
          path.join(
            process.env.XDG_CONFIG_HOME ?? path.join(os.homedir(), ".config"),
            "opencode/plugins",
            name,
          ),
        )
      )
        throw new Error(
          "Run opencode/install.sh to migrate the original OCX orchestration components before using the replacement.",
        );
    }
    const memory = await loadMemoryBaseline();
    const baseline = await memory.plugin(ctx);
    const { hooks, managerFor } = await regularHooks(ctx, effective);
    const memoryHooks = createRegularMemoryHooks(ctx, {
      baseline,
      storage: memory.storage,
      async isRoot(sessionID) {
        const session = await ctx.client.session.get({
          path: { id: sessionID },
        });
        if (session.error || !session.data)
          throw new Error("Cannot resolve memory session scope.");
        return !session.data.parentID;
      },
      async withConsolidation(sessionID, run) {
        return (await managerFor(sessionID)).consolidate(sessionID, run);
      },
    });
    return combineHooks(hooks, memoryHooks);
  });
};

export default Orchestrator;
