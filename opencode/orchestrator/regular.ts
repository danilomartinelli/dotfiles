import {
  tool,
  type Config,
  type Hooks,
  type PluginInput,
} from "@opencode-ai/plugin";
import { randomUUID } from "node:crypto";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { assertWriteTargets, childRoles, type Routes } from "./delegations";
import {
  admitOrchestration,
  assertReadOnlyTool,
  roleMayWrite,
} from "./permissions";
import { prompts, rolePermissions } from "./prompts";
import { SessionJournals } from "./session-journals";
import { directoryContext, prepareRead } from "./read-context";
import { CodeGraphProjects } from "./codegraph";

export async function regularHooks(ctx: PluginInput, declared: Config) {
  const profile = process.env.DOTFILES_OPENCODE_PROFILE_CONFIG;
  if (profile) {
    declared = (await import(pathToFileURL(profile).href)).default as Config;
    if (!declared.model || !declared.small_model)
      throw new Error(
        "The selected profile must declare default and small models.",
      );
  }
  const model = declared.model;
  const smallModel = declared.small_model;
  const routes = Object.fromEntries(
    ["plan", "build", ...childRoles].map((role) => {
      const agent = declared.agent?.[role];
      if (!agent?.model || !agent.variant)
        throw new Error(`Missing declared route: ${role}`);
      return [role, { model: agent.model, variant: agent.variant }];
    }),
  ) as Routes;
  const journals = new SessionJournals(
    path.join(os.homedir(), ".local/share/opencode/orchestrator"),
    ctx.client,
    routes,
  );
  const managerFor = (sessionID: string) => journals.forSession(sessionID);
  const roles = new Map<string, string>();
  const codegraph = new CodeGraphProjects();
  let codegraphEnabled = false;
  let mcpServers: string[] = [];
  async function rootFor(sessionID: string) {
    const manager = await managerFor(sessionID);
    const child = manager.forChild(sessionID);
    if (child) return child.root;
    await manager.assertRoot(sessionID);
    return sessionID;
  }
  async function resolveRole(sessionID: string): Promise<string> {
    const manager = await managerFor(sessionID);
    const child = manager.forChild(sessionID);
    if (child) return child.role;
    if (roles.has(sessionID)) return roles.get(sessionID)!;
    const result = await ctx.client.session.messages({
      path: { id: sessionID },
    });
    if (result.error) throw new Error("Cannot resolve agent capabilities.");
    const info = result.data?.at(-1)?.info;
    // Native v1.18.30 assistants carry `agent`; the legacy SDK still declares `mode`.
    const role =
      info && "agent" in info
        ? info.agent
        : info?.role === "assistant"
          ? info.mode
          : undefined;
    if (
      !role ||
      !Object.hasOwn(routes, role) ||
      !["build", "plan"].includes(role)
    )
      throw new Error(
        "Root sessions must use build/plan; enter child roles through delegate.",
      );
    return role;
  }
  async function notifyRoot(root: string, rootDirectory: string) {
    const manager = await managerFor(root);
    const notices = manager.notifications(root, true);
    if (!notices.length) return;
    // One batch wakes the existing root; no metadata or notification session.
    try {
      const role = await resolveRole(root);
      const route = routes[role];
      const [providerID, ...modelID] = route.model.split("/");
      const body = {
        agent: role,
        model: { providerID, modelID: modelID.join("/") },
        variant: route.variant,
        parts: [
          {
            type: "text" as const,
            text: `Delegation results ready:\n${notices.map((notice) => notice.text).join("\n")}\nRead the records and continue authorized work. Respect stopping reservations; resume terminal failures on the same delegation.`,
          },
        ],
      };
      const response = await ctx.client.session.promptAsync({
        path: { id: root },
        query: { directory: rootDirectory },
        body,
      });
      if (response.error) manager.restoreNotifications(root, notices);
    } catch {
      manager.restoreNotifications(root, notices);
    }
  }
  journals.onStopped = (row) => notifyRoot(row.root, row.rootDirectory);

  const hooks: Hooks = {
    config: async (config) => {
      config.model = model;
      config.small_model = smallModel;
      mcpServers = Object.keys(config.mcp ?? {});
      codegraphEnabled = Boolean(
        config.mcp?.codegraph && config.mcp.codegraph.enabled !== false,
      );
      config.agent ??= {};
      for (const role of new Set([
        ...Object.keys(config.agent),
        "general",
        "explore",
        "summary",
        "title",
      ])) {
        if (!Object.hasOwn(routes, role) && role !== "compaction")
          config.agent[role] = { disable: true };
      }
      for (const [role, route] of Object.entries(routes)) {
        config.agent ??= {};
        const agent = config.agent[role] ?? {};
        config.agent[role] = {
          ...agent,
          ...route,
          disable: false,
          temperature: undefined,
          prompt: prompts[role],
          mode: role === "plan" || role === "build" ? "primary" : "subagent",
          permission: rolePermissions(
            role,
            config.mcp,
            config.permission,
            agent.permission,
          ) as NonNullable<typeof agent>["permission"],
        };
      }
      config.permission = Object.assign({}, config.permission, {
        task: "deny" as const,
      });
      // Core compaction inherits the current user's model when this internal
      // agent has no model override. The parameter hook enforces that role's route.
      config.agent ??= {};
      config.agent.title = { disable: true };
      config.agent.compaction = {
        ...config.agent.compaction,
        model: undefined,
        variant: undefined,
        mode: "subagent",
        hidden: true,
        permission: { "*": "deny" } as NonNullable<
          NonNullable<Config["agent"]>[string]
        >["permission"],
      };
    },
    tool: {
      delegate: tool({
        description:
          "Run a declared role asynchronously: coder implements/verifies, scribe documents, explore investigates code, researcher retrieves external facts, reviewer reviews a source snapshot. Supply one focus in prompt; maximum three active. Resume the same delegation ID for corrections; each record reports its attempt count. List literal files/directories inside directory for every source/config/docs write. In Git checkouts, coder may use ownership: [] for verification or permitted MCP work; its automatic ignored artifact directory and the worktree's shared workspace are then its entire writable scope. Do not invent a source path for query-only work. Scribe and coder outside Git require explicit ownership; read-only roles require empty ownership. Only reviewer needs review_snapshot. Models come from the profile.",
        args: {
          role: tool.schema.enum(childRoles),
          workItem: tool.schema.string().min(1).max(200),
          directory: tool.schema.string(),
          ownership: tool.schema.array(tool.schema.string()).max(100),
          prompt: tool.schema.string().min(1).max(24000),
          sourceVersion: tool.schema.string().optional(),
          resume: tool.schema.string().optional(),
        },
        async execute(args, context) {
          const manager = await managerFor(context.sessionID);
          return JSON.stringify(await manager.start(context.sessionID, args));
        },
      }),
      delegation_list: tool({
        description:
          "Read delegation statuses and recorded routes; use after notifications, not polling.",
        args: {},
        async execute(_args, context) {
          const manager = await managerFor(context.sessionID);
          // Root identity precedes recovery: a child cannot enumerate, nor
          // trigger the recovery that enumeration prepares.
          await manager.assertRoot(context.sessionID);
          return JSON.stringify(
            (await manager.reconciledList(context.sessionID)).map(
              ({ result, ...row }) => row,
            ),
          );
        },
      }),
      delegation_read: tool({
        description:
          "Read the retained result of a delegation in this root session. Running results never block.",
        args: { id: tool.schema.string() },
        async execute(args, context) {
          const manager = await managerFor(context.sessionID);
          const root = await rootFor(context.sessionID);
          return JSON.stringify(await manager.reconciledRecord(root, args.id));
        },
      }),
      delegation_cancel: tool({
        description:
          "Abort a delegation, retaining its session and diagnostics. A stopping result is unconfirmed and still reserves its capacity/ownership.",
        args: { id: tool.schema.string() },
        async execute(args, context) {
          const manager = await managerFor(context.sessionID);
          await manager.assertRoot(context.sessionID);
          return JSON.stringify(await manager.stop(context.sessionID, args.id));
        },
      }),
      review_snapshot: tool({
        description:
          "Hash current HEAD, staged/unstaged changes and untracked content after writers finish; bind reviewers to the returned source version.",
        args: { directory: tool.schema.string() },
        async execute(args, context) {
          const manager = await managerFor(context.sessionID);
          return manager.reviewSnapshot(
            context.sessionID,
            args.directory,
            codegraphEnabled
              ? (directory) => codegraph.prepare(directory)
              : undefined,
          );
        },
      }),
      plan_save: tool({
        description:
          "Save a bounded Markdown plan for this root. Saving a plan never triggers a review.",
        args: { content: tool.schema.string().min(1).max(24000) },
        async execute(args, context) {
          const manager = await managerFor(context.sessionID);
          await manager.assertRoot(context.sessionID);
          manager.savePlan(context.sessionID, args.content);
          return "Plan saved.";
        },
      }),
      plan_read: tool({
        description: "Read this work item's saved plan.",
        args: {},
        async execute(_args, context) {
          const manager = await managerFor(context.sessionID);
          return manager.readPlan(await rootFor(context.sessionID));
        },
      }),
    },
    "chat.message": async (input, output) => {
      const manager = await managerFor(input.sessionID);
      const child = manager.forChild(input.sessionID);
      const role = child?.role ?? input.agent ?? output.message.agent;
      if (!role || !Object.hasOwn(routes, role))
        throw new Error(
          "Select a role declared by the profile; the profile owns model routing.",
        );
      if (
        child &&
        (child.messageID !== output.message.id ||
          !["starting", "running"].includes(child.status))
      )
        throw new Error(
          "Resume this child through delegate; direct prompts cannot bypass its generation and ownership reservation.",
        );
      if (!child && !["build", "plan"].includes(role))
        throw new Error(
          "Root sessions must use build/plan; enter child roles through delegate.",
        );
      const route = routes[role];
      if (
        child &&
        (child.route.model !== route.model ||
          child.route.variant !== route.variant)
      )
        throw new Error(
          "The profile route changed since this child started; finish/cancel it before creating a new delegation.",
        );
      const [providerID, ...modelID] = route.model.split("/");
      // Plugin hooks receive the native message shape, despite the stale v1 SDK.
      Object.assign(output.message, {
        agent: role,
        model: {
          providerID,
          modelID: modelID.join("/"),
          variant: route.variant,
        },
      });
      Reflect.deleteProperty(output.message, "variant");
      if (child || !roles.has(input.sessionID))
        output.parts.push({
          id: `prt_${randomUUID().replaceAll("-", "")}`,
          sessionID: input.sessionID,
          messageID: output.message.id,
          type: "text",
          text: [
            directoryContext(
              (await journals.session(input.sessionID)).directory,
            ),
            codegraphEnabled
              ? (
                  await codegraph.prepare(
                    (await journals.session(input.sessionID)).directory,
                  )
                ).notice
              : "",
          ]
            .filter(Boolean)
            .join("\n"),
          synthetic: true,
        });
      roles.set(input.sessionID, role);
      if (!child) {
        const session = await manager.assertRoot(input.sessionID);
        if (/^(New|Child) session - /.test(session.title)) {
          const text = output.parts.find(
            (part) => part.type === "text" && !part.synthetic,
          );
          if (text?.type === "text") {
            const title = text.text.replace(/\s+/g, " ").trim().slice(0, 100);
            if (title)
              await ctx.client.session.update({
                path: { id: input.sessionID },
                body: { title },
              });
          }
        }
        const notices = await manager.reconciledNotifications(input.sessionID);
        if (notices.length)
          output.parts.push({
            id: `prt_${randomUUID().replaceAll("-", "")}`,
            sessionID: input.sessionID,
            messageID: output.message.id,
            type: "text",
            text: notices.map((notice) => notice.text).join("\n"),
            synthetic: true,
          });
      }
    },
    "chat.params": async (input, output) => {
      const manager = await managerFor(input.sessionID);
      const child = manager.forChild(input.sessionID);
      const role =
        input.agent === "compaction"
          ? (child?.role ?? input.message.agent)
          : input.agent;
      if (child && role !== child.role)
        throw new Error("The child cannot change its declared agent role.");
      if (!child && !["build", "plan"].includes(role))
        throw new Error(
          "Only declared root roles and their internal compaction may request a model.",
        );
      const route = Object.hasOwn(routes, role) ? routes[role] : undefined;
      if (
        !route ||
        `${input.model.providerID}/${input.model.id}` !== route.model
      )
        throw new Error(
          "Effective model differs from the profile route; no request was sent.",
        );
      output.options.reasoningEffort = route.variant;
    },
    "tool.execute.before": async (input, output) => {
      const manager = await managerFor(input.sessionID);
      const role = await resolveRole(input.sessionID);
      const scope = admitOrchestration(role, input.tool, output.args);
      if (scope === "root") await manager.assertRoot(input.sessionID);
      if (scope) return;
      const child = manager.forChild(input.sessionID);
      const mcpExecution =
        role === "coder" &&
        mcpServers.some((server) => input.tool.startsWith(`${server}_`));
      if (roleMayWrite(role, input.tool)) {
        if (!child)
          throw new Error(
            "Writer edits require a delegation with file ownership.",
          );
        await assertWriteTargets(input.tool, output.args, child);
      }
      assertReadOnlyTool(role, input.tool, output.args);
      if (input.tool === "codegraph_codegraph_explore")
        await codegraph.query(
          output.args,
          (await journals.session(input.sessionID)).directory,
        );
      await prepareRead(
        input.tool,
        output.args,
        (await journals.session(input.sessionID)).directory,
      );
      if (roleMayWrite(role, input.tool) || mcpExecution)
        manager.toolStarted(input.sessionID, input.callID);
    },
    "shell.env": async (input) => {
      if (input.sessionID && input.callID) {
        const manager = await managerFor(input.sessionID);
        manager.toolStarted(input.sessionID, input.callID);
      }
    },
    "tool.execute.after": async (input) => {
      const manager = await managerFor(input.sessionID);
      await manager.toolFinished(input.sessionID, input.callID);
    },
    "experimental.session.compacting": async (input, output) => {
      const manager = await managerFor(input.sessionID);
      const root = await rootFor(input.sessionID);
      const { plan, records } = await manager.compactionContext(root);
      output.context.push(
        directoryContext((await journals.session(input.sessionID)).directory),
        `Orchestration recovery:\n${plan}\n${JSON.stringify(records.map(({ result, ...row }) => row))}\nRead retained results by delegation ID; resume only the same work item/role/focus. Do not recreate children after compaction.`,
      );
    },
    event: async ({ event }) => {
      if (
        event.type !== "session.idle" &&
        !(
          event.type === "session.status" &&
          event.properties.status.type === "idle"
        )
      )
        return;
      const manager = await managerFor(event.properties.sessionID);
      const child = manager.forChild(event.properties.sessionID);
      if (!child) return;
      await manager.complete(child.child!);
      await notifyRoot(child.root, child.rootDirectory);
    },
    dispose: async () => journals.close(),
  };
  return { hooks, managerFor };
}
