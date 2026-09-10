import { expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import {
  mkdtemp,
  mkdir,
  realpath,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

type ProviderRequest = {
  model: string;
  reasoning?: { effort?: string };
  input: unknown[];
  tools?: Array<{ name: string }>;
};

const mcpQueries = [
  {
    server: "context7",
    name: "resolve-library-id",
    arguments: { libraryName: "fixture", query: "Read fixture documentation" },
  },
  {
    server: "context7",
    name: "query-docs",
    arguments: {
      libraryId: "/example/fixture",
      query: "Read fixture documentation",
    },
  },
  {
    server: "exa",
    name: "web_search_exa",
    arguments: {
      query: "Fixture documentation",
      objective: "Find the fixture guide",
    },
  },
  {
    server: "exa",
    name: "web_fetch_exa",
    arguments: { urls: ["https://example.invalid/guide"], maxCharacters: 6000 },
  },
  {
    server: "gh_grep",
    name: "searchGitHub",
    arguments: { query: "fixture()" },
  },
];

function latestDelegation(request: ProviderRequest) {
  for (const item of request.input.toReversed()) {
    if (
      !item ||
      typeof item !== "object" ||
      Reflect.get(item, "type") !== "function_call_output"
    )
      continue;
    try {
      const record = JSON.parse(Reflect.get(item, "output"));
      if (record.id && record.role === "coder") return record;
    } catch {
      // Other tools return plain text rather than a delegation record.
    }
  }
  throw new Error(
    "Mock model did not receive a delegation ID to resume/cancel.",
  );
}

function responseEvents(
  model: string,
  result: { text: string } | { name: string; arguments: object },
) {
  const id = crypto.randomUUID().replaceAll("-", "");
  const response = {
    id: `resp_${id}`,
    object: "response",
    created_at: Math.floor(Date.now() / 1000),
    model,
    status: "in_progress",
  };
  const item =
    "text" in result
      ? {
          id: `msg_${id}`,
          type: "message",
          role: "assistant",
          status: "completed",
          content: [
            { type: "output_text", text: result.text, annotations: [] },
          ],
        }
      : {
          id: `fc_${id}`,
          type: "function_call",
          call_id: `call_${id}`,
          name: result.name,
          arguments: JSON.stringify(result.arguments),
          status: "completed",
        };
  const events: object[] = [
    { type: "response.created", response },
    {
      type: "response.output_item.added",
      output_index: 0,
      item:
        "text" in result
          ? { ...item, status: "in_progress", content: [] }
          : { ...item, status: "in_progress", arguments: "" },
    },
  ];
  if ("text" in result) {
    events.push(
      {
        type: "response.content_part.added",
        item_id: item.id,
        output_index: 0,
        content_index: 0,
        part: { type: "output_text", text: "", annotations: [] },
      },
      {
        type: "response.output_text.delta",
        item_id: item.id,
        output_index: 0,
        content_index: 0,
        delta: result.text,
      },
      {
        type: "response.output_text.done",
        item_id: item.id,
        output_index: 0,
        content_index: 0,
        text: result.text,
      },
    );
  } else {
    events.push({
      type: "response.function_call_arguments.delta",
      item_id: item.id,
      output_index: 0,
      delta: JSON.stringify(result.arguments),
    });
  }
  events.push(
    { type: "response.output_item.done", output_index: 0, item },
    {
      type: "response.completed",
      response: {
        ...response,
        status: "completed",
        output: [item],
        usage: {
          input_tokens: 10,
          output_tokens: 5,
          total_tokens: 15,
          input_tokens_details: { cached_tokens: 0 },
          output_tokens_details: { reasoning_tokens: 0 },
        },
      },
    },
  );
  return events
    .map((event, sequence_number) => {
      const value = { ...event, sequence_number };
      return `event: ${Reflect.get(event, "type")}\ndata: ${JSON.stringify(value)}\n\n`;
    })
    .join("");
}

async function until<T>(
  read: () => Promise<T | undefined>,
  description: string,
  milliseconds = 15000,
): Promise<T> {
  const deadline = Date.now() + milliseconds;
  while (Date.now() < deadline) {
    const value = await read();
    if (value !== undefined) return value;
    await Bun.sleep(25);
  }
  throw new Error(`Timed out waiting for ${description}`);
}

test("native OpenCode initializes deferred tools and preserves routing and writer lifecycle", async () => {
  const binary = Bun.which("opencode");
  if (!binary)
    throw new Error("Native integration requires the installed opencode CLI.");
  const root = await mkdtemp(join(tmpdir(), "opencode-native-"));
  const directory = join(root, "repository");
  const sessionDirectory = join(directory, "packages/app/src");
  const nonGitDirectory = join(root, "outside/repository");
  const configDirectory = join(root, "config/opencode");
  const profileConfig = join(root, "profile.jsonc");
  await mkdir(directory, { recursive: true });
  await mkdir(sessionDirectory, { recursive: true });
  await mkdir(join(directory, "src"));
  await writeFile(join(directory, "src/native.txt"), "before native patch\n");
  await mkdir(configDirectory, { recursive: true });
  for (const [base, name] of [
    [root, "global-fixture"],
    [directory, "project-fixture"],
    [join(directory, "packages/app"), "ancestor-fixture"],
    [nonGitDirectory, "non-git-fixture"],
  ]) {
    const skill = join(base, ".agents/skills", name);
    await mkdir(skill, { recursive: true });
    await writeFile(
      join(skill, "SKILL.md"),
      `---\nname: ${name}\ndescription: Isolated discovery fixture.\n---\nFixture skill.\n`,
    );
  }
  const explicitSkills = join(root, "explicit-skills");
  await mkdir(explicitSkills);
  await writeFile(
    join(explicitSkills, "SKILL.md"),
    "---\nname: explicit-fixture\ndescription: Explicit path fixture.\n---\nFixture skill.\n",
  );
  const env = {
    HOME: root,
    PATH: process.env.PATH!,
    SHELL: "/bin/sh",
    TMPDIR: root,
    XDG_CONFIG_HOME: join(root, "config"),
    XDG_DATA_HOME: join(root, "data"),
    XDG_STATE_HOME: join(root, "state"),
    XDG_CACHE_HOME: join(root, "cache"),
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_TERMINAL_PROMPT: "0",
    OPENCODE_TEST_HOME: root,
    OPENCODE_TEST_MANAGED_CONFIG_DIR: join(root, "managed"),
    OPENCODE_CONFIG: profileConfig,
    DOTFILES_OPENCODE_PROFILE_CONFIG: profileConfig,
    OPENCODE_DISABLE_MODELS_FETCH: "true",
    OPENCODE_DISABLE_AUTOUPDATE: "true",
    OPENCODE_DISABLE_DEFAULT_PLUGINS: "true",
    OPENCODE_DISABLE_EXTERNAL_SKILLS: "true",
    OPENCODE_DISABLE_CLAUDE_CODE: "true",
    OPENCODE_DISABLE_LSP_DOWNLOAD: "true",
    OPENCODE_DISABLE_SHARE: "true",
    OPENCODE_DISABLE_FFF: "true",
    OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER: "true",
  };
  const requests: ProviderRequest[] = [];
  const issued = new Set<string>();
  let activeNativeCalls: (() => number) | undefined;
  const nativeAfterReady = join(root, "native-after-ready");
  const releaseNativeAfter = join(root, "release-native-after");
  const nativePatchJournal = join(root, "native-patch-journal.json");
  let mcpStarted = false;
  let mcpFinished = false;
  let mcpCalls = 0;
  const mcpReadCalls: Array<{
    server: string;
    name: string;
    arguments: unknown;
  }> = [];
  let releaseMcp!: () => void;
  const mcpPending = new Promise<void>((resolve) => {
    releaseMcp = resolve;
  });
  const mock = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    async fetch(request) {
      const pathname = new URL(request.url).pathname;
      const queryServer = pathname.match(
        /^\/queries\/(context7|exa|gh_grep)$/,
      )?.[1];
      if (pathname === "/mcp" || queryServer) {
        if (request.method !== "POST")
          return new Response(null, { status: 405 });
        const body = (await request.json()) as {
          id?: number;
          method: string;
          params?: {
            protocolVersion?: string;
            name?: string;
            arguments?: unknown;
          };
        };
        if (body.id === undefined) return new Response(null, { status: 202 });
        let result: object;
        if (body.method === "initialize") {
          result = {
            protocolVersion: body.params?.protocolVersion,
            capabilities: { tools: {} },
            serverInfo: { name: "fixture", version: "1" },
          };
        } else if (body.method === "tools/list") {
          result = {
            tools: queryServer
              ? [
                  ...mcpQueries
                    .filter((query) => query.server === queryServer)
                    .map((query) => ({
                      name: query.name,
                      description: "Read isolated fixture documentation.",
                      annotations: { readOnlyHint: true },
                      inputSchema: {
                        type: "object",
                        properties: Object.fromEntries(
                          Object.entries(query.arguments).map(
                            ([name, value]) => [
                              name,
                              Array.isArray(value)
                                ? { type: "array", items: { type: "string" } }
                                : { type: typeof value },
                            ],
                          ),
                        ),
                      },
                    })),
                  {
                    name: "unknown_read",
                    description:
                      "An unapproved tool, even when advertised as read-only.",
                    annotations: { readOnlyHint: true },
                    inputSchema: { type: "object", properties: {} },
                  },
                ]
              : [
                  {
                    name: "update_item",
                    description: "Wait for the isolated operation to finish.",
                    inputSchema: { type: "object", properties: {} },
                  },
                ],
          };
        } else if (body.method === "tools/call") {
          if (queryServer) {
            mcpReadCalls.push({
              server: queryServer,
              name: body.params!.name!,
              arguments: body.params!.arguments,
            });
          } else if (++mcpCalls === 2) {
            mcpStarted = true;
            await mcpPending;
            mcpFinished = true;
          }
          result = {
            content: [{ type: "text", text: "Native MCP operation finished." }],
          };
        } else return new Response(null, { status: 400 });
        return Response.json({ jsonrpc: "2.0", id: body.id, result });
      }
      if (new URL(request.url).pathname !== "/v1/responses")
        return new Response("Only local Responses requests are permitted", {
          status: 400,
        });
      const body = (await request.json()) as ProviderRequest;
      requests.push(body);
      const input = JSON.stringify(body.input);
      const marker = input.includes("NATIVE_MCP_CANCEL_ROOT")
        ? "NATIVE_MCP_CANCEL_ROOT"
        : input.includes("NATIVE_MCP_ROOT")
          ? "NATIVE_MCP_ROOT"
          : input.includes("NATIVE_CANCEL_ROOT")
            ? "NATIVE_CANCEL_ROOT"
            : input.includes("NATIVE_RESUME_ROOT")
              ? "NATIVE_RESUME_ROOT"
              : input.includes("NATIVE_BAD_ROLE")
                ? "NATIVE_BAD_ROLE"
                : input.includes("NATIVE_VALID_ROOT")
                  ? "NATIVE_VALID_ROOT"
                  : undefined;
      let output: Parameters<typeof responseEvents>[1] = {
        text: "Verified fixture result.",
      };
      const inspection = [
        "git rev-parse --show-toplevel",
        "GIT_NO_LAZY_FETCH=1 'git' '--no-pager' '--no-optional-locks' '-c' 'core.fsmonitor=false' 'rev-parse' '--show-toplevel'",
      ].find((command) => !issued.has(command));
      const mcpQuery = mcpQueries.find(
        (query) => !issued.has(`${query.server}_${query.name}`),
      );
      if (marker === "NATIVE_VALID_ROOT" && mcpQuery) {
        const name = `${mcpQuery.server}_${mcpQuery.name}`;
        issued.add(name);
        output = { name, arguments: mcpQuery.arguments };
      } else if (marker === "NATIVE_VALID_ROOT" && inspection) {
        issued.add(inspection);
        output = {
          name: "bash",
          arguments: {
            command: inspection,
            description: "Inspect the checkout from the read-only root",
          },
        };
      } else if (input.includes("NATIVE_REVIEW_ROOT")) {
        if (!issued.has("review-snapshot")) {
          issued.add("review-snapshot");
          output = { name: "review_snapshot", arguments: { directory } };
        } else {
          const focus = ["data preservation", "caller compatibility"].find(
            (focus) => !issued.has(focus),
          );
          if (focus) {
            const snapshot = body.input.find(
              (item: any) =>
                item.type === "function_call_output" &&
                /^[a-f0-9]{40,64}:[a-f0-9]{64}$/.test(item.output),
            ) as { output: string } | undefined;
            if (!snapshot)
              throw new Error("Native review_snapshot result is missing");
            issued.add(focus);
            output = {
              name: "delegate",
              arguments: {
                role: "reviewer",
                workItem: "native-review",
                directory,
                ownership: [],
                sourceVersion: snapshot.output,
                prompt: `NATIVE_REVIEW_FOCUS: ${focus}. Check src/native.txt and return evidence.`,
              },
            };
          }
        }
      } else if (marker && !issued.has(marker)) {
        issued.add(marker);
        output = {
          name: "delegate",
          arguments: {
            role: marker === "NATIVE_BAD_ROLE" ? "coder-complex" : "coder",
            workItem: "native-fixture",
            directory,
            ownership: ["src"],
            prompt:
              marker === "NATIVE_MCP_CANCEL_ROOT"
                ? "NATIVE_MCP_CANCEL_CHILD. Run the pending project fixture MCP operation."
                : marker === "NATIVE_MCP_ROOT"
                  ? "NATIVE_MCP_CHILD. Run the project fixture MCP operation."
                  : marker === "NATIVE_CANCEL_ROOT"
                    ? "NATIVE_CANCEL_CHILD. Run the cancellable fixture command."
                    : marker === "NATIVE_RESUME_ROOT"
                      ? "NATIVE_RESUMED_CHILD. Validate the same slice again."
                      : "NATIVE_CHILD_WORK. Validate the bounded slice with Bash.",
            ...([
              "NATIVE_RESUME_ROOT",
              "NATIVE_CANCEL_ROOT",
              "NATIVE_MCP_CANCEL_ROOT",
              "NATIVE_MCP_ROOT",
            ].includes(marker)
              ? { resume: latestDelegation(body).id }
              : {}),
          },
        };
      } else if (
        body.model === "gpt-5.6-sol" &&
        ["NATIVE_CANCEL_ROOT", "NATIVE_MCP_CANCEL_ROOT"].includes(
          marker ?? "",
        ) &&
        !issued.has(`${marker}_CALL`)
      ) {
        await until(
          async () =>
            activeNativeCalls?.() === 1 &&
            (marker !== "NATIVE_MCP_CANCEL_ROOT" || mcpStarted)
              ? true
              : undefined,
          "native tool reservation before cancellation",
        );
        issued.add(`${marker}_CALL`);
        output = {
          name: "delegation_cancel",
          arguments: { id: latestDelegation(body).id },
        };
      }
      const mcpMarker = input.includes("NATIVE_MCP_CANCEL_CHILD")
        ? "NATIVE_MCP_CANCEL_CHILD"
        : "NATIVE_MCP_CHILD";
      if (
        body.model === "gpt-5.6-luna" &&
        input.includes(mcpMarker) &&
        !issued.has(mcpMarker)
      ) {
        issued.add(mcpMarker);
        output = { name: "fixture_update_item", arguments: {} };
      }
      const bashMarker = input.includes("NATIVE_CANCEL_CHILD")
        ? "NATIVE_CANCEL_CHILD"
        : input.includes("NATIVE_RESUMED_CHILD")
          ? "NATIVE_RESUMED_CHILD"
          : "NATIVE_CHILD_WORK";
      if (
        body.model === "gpt-5.6-luna" &&
        input.includes(bashMarker) &&
        !issued.has(bashMarker)
      ) {
        issued.add(bashMarker);
        output = {
          name: "bash",
          arguments: {
            command:
              bashMarker === "NATIVE_CANCEL_CHILD"
                ? "sleep 30"
                : `printf '${bashMarker}: native-bash-ok'`,
            description: `${bashMarker}: validate the fixture with a real shell command`,
          },
        };
      }
      if (
        body.model === "gpt-5.6-luna" &&
        input.includes("NATIVE_CHILD_WORK") &&
        "text" in output &&
        !issued.has("NATIVE_CHILD_PATCH")
      ) {
        issued.add("NATIVE_CHILD_PATCH");
        output = {
          name: "apply_patch",
          arguments: {
            patchText:
              "*** Begin Patch\n*** Update File: src/native.txt\n@@\n-before native patch\n+after native patch\n*** End Patch",
          },
        };
      }
      return new Response(responseEvents(body.model, output), {
        headers: { "Content-Type": "text/event-stream" },
      });
    },
  });
  let server: ReturnType<typeof Bun.spawn> | undefined;
  let orchestration: Database | undefined;
  let logs = "";
  const logTasks: Promise<void>[] = [];
  try {
    const version = Bun.spawnSync({ cmd: [binary, "--version"], env });
    expect(version.stdout.toString().trim()).toBe("1.18.23");
    const git = Bun.spawnSync({
      cmd: ["git", "init", directory],
      env,
      stderr: "pipe",
    });
    expect(git.exitCode).toBe(0);
    const commit = Bun.spawnSync({
      cmd: [
        "git",
        "-C",
        directory,
        "-c",
        "user.name=Fixture",
        "-c",
        "user.email=fixture@example.invalid",
        "commit",
        "--allow-empty",
        "-m",
        "Fixture",
      ],
      env,
    });
    expect(commit.exitCode).toBe(0);
    const pluginUrl = new URL(
      "../opencode/orchestrator/regular.ts",
      import.meta.url,
    ).href;
    const plugin = join(root, "fixture-plugin.ts");
    const hooksUrl = new URL(
      "../opencode/orchestrator/hooks.ts",
      import.meta.url,
    ).href;
    // Pause only the acknowledgement of an already-returned native Bash call.
    // The real process, abort API, plugin hooks, and persisted ledger still run.
    await writeFile(
      plugin,
      `import { Database } from "bun:sqlite";
import { regularHooks } from ${JSON.stringify(pluginUrl)};
import { initializeFromConfig } from ${JSON.stringify(hooksUrl)};
export default async ctx => initializeFromConfig(async config => {
  const { hooks } = await regularHooks(ctx, config);
  const after = hooks["tool.execute.after"];
  hooks["tool.execute.after"] = async (input, output) => {
    if (input.tool === "apply_patch") {
      const journal = new Database(${JSON.stringify(join(root, ".local/share/opencode/orchestrator"))} + "/" + ctx.project.id + ".sqlite", { readonly: true });
      try {
        const outstanding = journal.query("SELECT count(*) AS count FROM tool_calls WHERE id=? AND child=?").get(input.callID, input.sessionID);
        await Bun.write(${JSON.stringify(nativePatchJournal)}, JSON.stringify(outstanding));
      } finally {
        journal.close();
      }
    }
    if (input.tool === "bash" && input.args.description?.startsWith("NATIVE_CANCEL_CHILD")) {
      await Bun.write(${JSON.stringify(nativeAfterReady)}, "ready");
      const deadline = Date.now() + 10000;
      while (!(await Bun.file(${JSON.stringify(releaseNativeAfter)}).exists())) {
        if (Date.now() > deadline) throw new Error("Native acknowledgement fixture was not released");
        await Bun.sleep(5);
      }
    }
    await after?.(input, output);
  };
  return hooks;
});\n`,
    );
    const dependencyDirectory = fileURLToPath(
      new URL("../opencode/orchestrator/node_modules", import.meta.url),
    );
    await mkdir(join(configDirectory, "node_modules/@opencode-ai"), {
      recursive: true,
    });
    await symlink(
      join(dependencyDirectory, "@opencode-ai/plugin"),
      join(configDirectory, "node_modules/@opencode-ai/plugin"),
    );
    await writeFile(
      join(configDirectory, "package.json"),
      JSON.stringify({ dependencies: { "@opencode-ai/plugin": "1.18.23" } }),
    );
    await writeFile(
      profileConfig,
      `// The direct adapter's routing source is independent of project overrides.\n${JSON.stringify(
        {
          model: "openai/gpt-5.6-sol",
          small_model: "openai/gpt-5.6-luna",
          agent: Object.fromEntries(
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
          ),
        },
      )}\n`,
    );
    await writeFile(
      join(directory, "opencode.json"),
      JSON.stringify({
        model: "openai/gpt-5.6-luna",
        small_model: "openai/gpt-5.6-sol",
        skills: { paths: [explicitSkills], urls: [] },
        mcp: {
          project: {
            type: "remote",
            url: "https://example.invalid/mcp",
            enabled: false,
          },
          fixture: { type: "remote", url: `http://127.0.0.1:${mock.port}/mcp` },
          ...Object.fromEntries(
            ["context7", "exa", "gh_grep"].map((server) => [
              server,
              {
                type: "remote",
                url: `http://127.0.0.1:${mock.port}/queries/${server}`,
              },
            ]),
          ),
        },
        agent: {
          coder: {
            model: "openai/gpt-5.6-sol",
            variant: "low",
            permission: { "project_*": "allow", "fixture_*": "allow" },
          },
        },
      }),
    );
    await writeFile(
      join(configDirectory, "opencode.json"),
      JSON.stringify({
        $schema: "https://opencode.ai/config.json",
        plugin: [plugin],
        enabled_providers: ["openai"],
        provider: {
          openai: {
            npm: "@ai-sdk/openai",
            options: {
              baseURL: `http://127.0.0.1:${mock.port}/v1`,
              apiKey: "fixture-key",
            },
            models: Object.fromEntries(
              ["gpt-5.6-sol", "gpt-5.6-luna"].map((id) => [
                id,
                {
                  name: id,
                  reasoning: true,
                  toolcall: true,
                  limit: { context: 200000, output: 8000 },
                },
              ]),
            ),
          },
        },
      }),
    );
    server = Bun.spawn({
      cmd: [
        binary,
        "serve",
        "--hostname",
        "127.0.0.1",
        "--port",
        "0",
        "--print-logs",
      ],
      cwd: directory,
      env,
      stdout: "pipe",
      stderr: "pipe",
    });
    for (const stream of [server.stdout, server.stderr]) {
      logTasks.push(
        (async () => {
          for await (const chunk of stream as ReadableStream<Uint8Array>)
            logs += new TextDecoder().decode(chunk);
        })(),
      );
    }
    const baseURL = await until(async () => {
      if (server!.exitCode !== null)
        throw new Error(`OpenCode exited: ${logs}`);
      return logs.match(/http:\/\/127\.0\.0\.1:\d+/)?.[0];
    }, "native server address");
    async function api(
      path: string,
      body?: object,
      targetDirectory = directory,
    ) {
      const response = await fetch(
        `${baseURL}${path}?directory=${encodeURIComponent(targetDirectory)}`,
        {
          method: body === undefined ? "GET" : "POST",
          headers: { "Content-Type": "application/json" },
          body: body === undefined ? undefined : JSON.stringify(body),
          signal: AbortSignal.timeout(20000),
        },
      );
      const text = await response.text();
      if (!response.ok)
        throw new Error(
          `Native API ${path}: ${response.status} ${text}\n${logs}`,
        );
      return text ? JSON.parse(text) : undefined;
    }
    const session = await api("/session", { title: "Native routing fixture" });
    const skills = await api("/skill", undefined, sessionDirectory);
    expect(skills.some((skill: any) => skill.name === "project-fixture")).toBe(
      true,
    );
    expect(skills.some((skill: any) => skill.name === "global-fixture")).toBe(
      false,
    );
    expect(skills.some((skill: any) => skill.name === "ancestor-fixture")).toBe(
      true,
    );
    expect(skills.some((skill: any) => skill.name === "explicit-fixture")).toBe(
      true,
    );
    const nonGitSkills = await api("/skill", undefined, nonGitDirectory);
    expect(
      nonGitSkills.some((skill: any) => skill.name === "non-git-fixture"),
    ).toBe(true);
    expect(
      nonGitSkills.some((skill: any) => skill.name === "global-fixture"),
    ).toBe(false);
    const configured = await api("/config");
    expect(configured.model).toBe("openai/gpt-5.6-sol");
    expect(configured.small_model).toBe("openai/gpt-5.6-luna");
    expect(configured.agent.coder.model).toBe("openai/gpt-5.6-luna");
    expect(configured.agent.coder.variant).toBe("high");
    expect(configured.skills.paths).toContain(explicitSkills);
    expect(configured.skills.urls).toEqual([]);
    expect(configured.mcp.project.enabled).toBe(false);
    expect(configured.agent.coder.permission["project_*"]).toBe("allow");
    expect(configured.agent.reviewer.permission["project_*"]).toBeUndefined();
    const result = await api(`/session/${session.id}/message`, {
      agent: "build",
      model: { providerID: "openai", modelID: "gpt-5.6-luna", variant: "low" },
      parts: [{ type: "text", text: "NATIVE_VALID_ROOT" }],
    });
    if (result.info?.error)
      throw new Error(JSON.stringify(result.info.error) + "\n" + logs);
    const rootMessages = await api(`/session/${session.id}/message`);
    const inspections = rootMessages
      .flatMap((message: any) => message.parts)
      .filter((part: any) => part.type === "tool" && part.tool === "bash");
    expect(inspections.map((part: any) => part.state.status)).toEqual([
      "completed",
      "completed",
    ]);
    for (const part of inspections)
      expect(part.state.output.trim()).toBe(await realpath(directory));
    expect(mcpReadCalls).toEqual(mcpQueries);
    for (const query of mcpQueries) {
      const part = rootMessages
        .flatMap((message: any) => message.parts)
        .find((part: any) => part.tool === `${query.server}_${query.name}`);
      expect(part?.state.status).toBe("completed");
    }
    const child = await until(async () => {
      const sessions = await api("/session");
      return sessions.find((item: any) => item.parentID === session.id);
    }, "declared coder child");
    orchestration = new Database(
      join(
        root,
        ".local/share/opencode/orchestrator",
        `${session.projectID}.sqlite`,
      ),
      { readonly: true },
    );
    function delegation() {
      const row = orchestration!
        .query("SELECT record FROM delegations ORDER BY rowid LIMIT 1")
        .get() as { record: string };
      return JSON.parse(row.record);
    }
    function pendingTools() {
      return (
        orchestration!
          .query("SELECT count(*) AS count FROM tool_calls")
          .get() as { count: number }
      ).count;
    }
    activeNativeCalls = pendingTools;
    const childMessages = await until(async () => {
      const messages = await api(`/session/${child.id}/message`);
      return messages.some(
        (message: any) =>
          message.info.role === "assistant" &&
          message.info.finish === "stop" &&
          message.info.time.completed,
      )
        ? messages
        : undefined;
    }, "coder completion");
    const rootRequest = requests.find((request) =>
      JSON.stringify(request.input).includes("NATIVE_VALID_ROOT"),
    );
    const childRequest = requests.find((request) =>
      JSON.stringify(request.input).includes(
        "Declared route: coder = openai/gpt-5.6-luna/high.",
      ),
    );
    expect(rootRequest?.model).toBe("gpt-5.6-sol");
    expect(rootRequest?.reasoning?.effort).toBe("xhigh");
    expect(
      rootRequest?.tools?.some((tool) => tool.name.endsWith("_unknown_read")),
    ).toBe(false);
    expect(childRequest?.model).toBe("gpt-5.6-luna");
    expect(childRequest?.reasoning?.effort).toBe("high");
    expect(
      childMessages.find((message: any) => message.info.role === "user").info
        .agent,
    ).toBe("coder");
    expect(child.title).toStartWith("coder: native-fixture");
    expect(rootRequest?.tools?.some((tool) => tool.name === "delegate")).toBe(
      true,
    );
    const nativeBash = childMessages
      .flatMap((message: any) => message.parts)
      .find((part: any) => part.type === "tool" && part.tool === "bash");
    expect(nativeBash?.state.status).toBe("completed");
    expect(nativeBash?.state.output).toContain(
      "NATIVE_CHILD_WORK: native-bash-ok",
    );
    expect(
      childRequest?.tools?.some((tool) => tool.name === "apply_patch"),
    ).toBe(true);
    const nativePatch = childMessages
      .flatMap((message: any) => message.parts)
      .find((part: any) => part.type === "tool" && part.tool === "apply_patch");
    expect(nativePatch?.state.status).toBe("completed");
    expect(nativePatch?.state.output).toContain("M src/native.txt");
    expect(await Bun.file(join(directory, "src/native.txt")).text()).toBe(
      "after native patch\n",
    );
    expect(await Bun.file(nativePatchJournal).json()).toEqual({ count: 1 });
    await until(
      async () => (delegation().status === "completed" ? true : undefined),
      "writer terminal state",
    );
    expect(pendingTools()).toBe(0);
    expect((await api("/session")).length).toBe(2);

    const firstGeneration = delegation().messageID;
    const resumed = await api(`/session/${session.id}/message`, {
      agent: "build",
      parts: [{ type: "text", text: "NATIVE_RESUME_ROOT" }],
    });
    if (resumed.info?.error)
      throw new Error(JSON.stringify(resumed.info.error) + "\n" + logs);
    await until(
      async () =>
        delegation().messageID !== firstGeneration &&
        delegation().status === "completed"
          ? true
          : undefined,
      "resumed writer terminal state",
    );
    const resumedMessages = await api(`/session/${child.id}/message`);
    const resumedBash = resumedMessages
      .flatMap((message: any) => message.parts)
      .filter((part: any) => part.type === "tool" && part.tool === "bash");
    expect(resumedBash).toHaveLength(2);
    expect(resumedBash[1].state.status).toBe("completed");
    expect(resumedBash[1].state.output).toContain(
      "NATIVE_RESUMED_CHILD: native-bash-ok",
    );
    expect(delegation().child).toBe(child.id);
    expect(pendingTools()).toBe(0);
    expect((await api("/session")).length).toBe(2);

    const bad = await api("/session", { title: "Native invalid role fixture" });
    const rejected = await api(`/session/${bad.id}/message`, {
      agent: "build",
      parts: [{ type: "text", text: "NATIVE_BAD_ROLE" }],
    });
    if (rejected.info?.error)
      throw new Error(JSON.stringify(rejected.info.error) + "\n" + logs);
    const badMessages = await api(`/session/${bad.id}/message`);
    expect(JSON.stringify(badMessages)).toContain("coder-complex");
    expect(
      badMessages
        .flatMap((message: any) => message.parts)
        .some(
          (part: any) => part.type === "tool" && part.state.status === "error",
        ),
    ).toBe(true);
    expect((await api("/session")).length).toBe(3);

    const beforeRootCompaction = requests.length;
    await api(`/session/${bad.id}/summarize`, {
      providerID: "openai",
      modelID: "gpt-5.6-sol",
    });
    const rootCompaction = requests.slice(beforeRootCompaction);
    expect(rootCompaction.length).toBeGreaterThan(0);
    expect(
      rootCompaction.every(
        (request) =>
          request.model === "gpt-5.6-sol" &&
          request.reasoning?.effort === "xhigh",
      ),
    ).toBe(true);
    const rootSummary = (await api(`/session/${bad.id}/message`)).find(
      (message: any) => message.info.agent === "compaction",
    );
    expect(rootSummary?.info.error).toBeUndefined();
    expect(rootSummary?.info.finish).toBe("stop");
    expect((await api("/session")).length).toBe(3);

    const beforeChildCompaction = requests.length;
    await api(`/session/${child.id}/summarize`, {
      providerID: "openai",
      modelID: "gpt-5.6-luna",
    });
    const childCompaction = requests.slice(beforeChildCompaction);
    expect(childCompaction.length).toBeGreaterThan(0);
    expect(
      childCompaction.every(
        (request) =>
          request.model === "gpt-5.6-luna" &&
          request.reasoning?.effort === "high",
      ),
    ).toBe(true);
    const childSummary = (await api(`/session/${child.id}/message`)).find(
      (message: any) => message.info.agent === "compaction",
    );
    expect(childSummary?.info.error).toBeUndefined();
    expect(childSummary?.info.finish).toBe("stop");
    expect((await api("/session")).length).toBe(3);

    const cancelling = api(`/session/${session.id}/message`, {
      agent: "build",
      parts: [{ type: "text", text: "NATIVE_CANCEL_ROOT" }],
    });
    await until(
      async () =>
        (await Bun.file(nativeAfterReady).exists()) ? true : undefined,
      "native Bash completion before acknowledgement",
    );
    expect(delegation().status).toBe("stopping");
    expect(pendingTools()).toBe(1);
    expect((await api("/session")).length).toBe(3);
    await writeFile(releaseNativeAfter, "release");
    const cancelledResponse = await cancelling;
    if (cancelledResponse.info?.error)
      throw new Error(
        JSON.stringify(cancelledResponse.info.error) + "\n" + logs,
      );
    await until(
      async () => (delegation().status === "cancelled" ? true : undefined),
      "cancelled writer after native acknowledgement",
    );
    expect(pendingTools()).toBe(0);
    expect(delegation().child).toBe(child.id);
    expect((await api("/session")).length).toBe(3);
    const agents = await api("/agent");
    expect(
      agents
        .filter((agent: any) => !agent.hidden)
        .map((agent: any) => agent.name)
        .sort(),
    ).toEqual([
      "build",
      "coder",
      "explore",
      "plan",
      "researcher",
      "reviewer",
      "scribe",
    ]);
    const reviewRoot = await api("/session", {
      title: "Native focused reviewers",
    });
    const reviewReply = await api(`/session/${reviewRoot.id}/message`, {
      agent: "build",
      parts: [{ type: "text", text: "NATIVE_REVIEW_ROOT" }],
    });
    if (reviewReply.info?.error)
      throw new Error(JSON.stringify(reviewReply.info.error) + "\n" + logs);
    const reviews = () =>
      orchestration!
        .query("SELECT record FROM delegations")
        .all()
        .map((row: any) => JSON.parse(row.record))
        .filter((row: any) => row.root === reviewRoot.id);
    await until(
      async () =>
        reviews().length === 2 &&
        reviews().every((row: any) => row.status === "completed")
          ? true
          : undefined,
      "two focused reviewers using the same role",
    );
    expect(
      reviews().every(
        (row: any) =>
          row.role === "reviewer" &&
          row.route.model === "openai/gpt-5.6-luna" &&
          row.route.variant === "high",
      ),
    ).toBe(true);
    const reviewRequests = requests.filter((request) =>
      request.input.some(
        (item: any) =>
          item.role === "user" &&
          JSON.stringify(item.content).includes("NATIVE_REVIEW_FOCUS"),
      ),
    );
    expect(reviewRequests.length).toBeGreaterThanOrEqual(2);
    expect(
      reviewRequests.every(
        (request) =>
          request.model === "gpt-5.6-luna" &&
          request.reasoning?.effort === "high",
      ),
    ).toBe(true);
    expect((await api("/session")).length).toBe(6);
    const mcpGeneration = delegation().messageID;
    const mcpResponse = await api(`/session/${session.id}/message`, {
      agent: "build",
      parts: [{ type: "text", text: "NATIVE_MCP_ROOT" }],
    });
    if (mcpResponse.info?.error)
      throw new Error(JSON.stringify(mcpResponse.info.error) + "\n" + logs);
    await until(
      async () =>
        delegation().messageID !== mcpGeneration &&
        delegation().status === "completed"
          ? true
          : undefined,
      "normal MCP completion acknowledgement",
    );
    expect(mcpCalls).toBe(1);
    expect(pendingTools()).toBe(0);
    const mcpMessages = await api(`/session/${child.id}/message`);
    const mcpTool = mcpMessages
      .flatMap((message: any) => message.parts)
      .find(
        (part: any) =>
          part.type === "tool" && part.tool === "fixture_update_item",
      );
    expect(mcpTool?.state.status).toBe("completed");
    expect(mcpTool?.state.output).toContain("Native MCP operation finished.");

    const cancellingMcp = api(`/session/${session.id}/message`, {
      agent: "build",
      parts: [{ type: "text", text: "NATIVE_MCP_CANCEL_ROOT" }],
    });
    await until(
      async () =>
        mcpStarted &&
        delegation().status === "stopping" &&
        delegation().abortAcknowledged
          ? true
          : undefined,
      "MCP execution retained after native abort acknowledgement",
    );
    expect(pendingTools()).toBe(1);
    expect(delegation().child).toBe(child.id);
    releaseMcp();
    const cancelledMcpResponse = await cancellingMcp;
    if (cancelledMcpResponse.info?.error)
      throw new Error(
        JSON.stringify(cancelledMcpResponse.info.error) + "\n" + logs,
      );
    await until(
      async () => (mcpFinished ? true : undefined),
      "remote MCP execution finished",
    );
    // Native MCP abort discards the eventual response and never emits after.
    // Remote completion alone cannot replace the missing acknowledgement.
    expect(delegation().status).toBe("stopping");
    expect(pendingTools()).toBe(1);
    expect(delegation().ownership).toEqual([
      await realpath(join(directory, "src")),
    ]);
    expect((await api("/session")).length).toBe(6);
    expect(logs).not.toMatch(
      /service=bun|installing dependencies|registry\.npmjs\.org/i,
    );
  } finally {
    releaseMcp();
    if (server) {
      server.kill("SIGTERM");
      await server.exited;
    }
    await Promise.all(logTasks);
    orchestration?.close();
    mock.stop(true);
    await rm(root, { recursive: true, force: true });
  }
}, 60000);
