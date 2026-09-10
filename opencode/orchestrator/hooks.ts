import type { Hooks } from "@opencode-ai/plugin";

/** Config is already available here; an SDK config request during init deadlocks. */
export function initializeFromConfig(
  initialize: (
    config: Parameters<NonNullable<Hooks["config"]>>[0],
  ) => Promise<Hooks>,
): Hooks {
  let implementation: Hooks | undefined;
  let failure: unknown;
  const published: Hooks = { tool: {} };
  published.config = async (config) => {
    try {
      implementation ??= await initialize(config);
      Object.assign(published.tool!, implementation.tool);
      await implementation.config?.(config);
    } catch (error) {
      failure = error;
      throw error;
    }
  };
  for (const key of [
    "dispose",
    "event",
    "chat.message",
    "chat.params",
    "chat.headers",
    "command.execute.before",
    "tool.execute.before",
    "tool.execute.after",
    "shell.env",
    "permission.ask",
    "experimental.chat.messages.transform",
    "experimental.chat.system.transform",
    "experimental.session.compacting",
    "experimental.text.complete",
  ]) {
    Reflect.set(published, key, async (...args: unknown[]) => {
      if (failure && key !== "dispose") throw failure;
      const hook = implementation && Reflect.get(implementation, key);
      if (typeof hook === "function") await hook(...args);
    });
  }
  return published;
}

/** Run orchestration before memory hooks; tool collisions are errors. */
export function combineHooks(...sources: Hooks[]): Hooks {
  const result: Record<string, unknown> = {};
  for (const hooks of sources) {
    for (const [key, value] of Object.entries(hooks)) {
      if (value === undefined) continue;
      if (key === "tool") {
        const previous = (result.tool ?? {}) as Record<string, unknown>;
        for (const name of Object.keys(value))
          if (name in previous)
            throw new Error(`Duplicate plugin tool: ${name}`);
        result.tool = { ...previous, ...value };
      } else if (typeof value === "function") {
        const previous = result[key] as
          ((...args: unknown[]) => Promise<void>) | undefined;
        result[key] = async (...args: unknown[]) => {
          await previous?.(...args);
          await value(...args);
        };
      } else throw new Error(`Unsupported composed plugin field: ${key}`);
    }
  }
  return result as Hooks;
}
