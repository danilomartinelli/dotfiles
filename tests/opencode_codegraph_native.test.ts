import { expect, test } from "bun:test";
import { mkdtemp, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { CodeGraphProjects } from "../opencode/orchestrator/codegraph";

test("installed CodeGraph initializes the checkout and exposes its approved MCP query", async () => {
  const binary = Bun.which("codegraph");
  if (!binary)
    throw new Error("Native integration requires the declared codegraph CLI.");
  const home = await realpath(
    await mkdtemp(path.join(tmpdir(), "codegraph-native-")),
  );
  const directory = path.join(home, "repository");
  const env = {
    HOME: home,
    PATH: process.env.PATH!,
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    CODEGRAPH_TELEMETRY: "0",
    CODEGRAPH_NO_UPDATE_CHECK: "1",
    CODEGRAPH_NO_DAEMON: "1",
    CODEGRAPH_QUERY_POOL_SIZE: "0",
  };
  let server: ReturnType<typeof Bun.spawn> | undefined;
  let drain: Promise<void> | undefined;
  let stderr: Promise<string> | undefined;
  try {
    expect(Bun.spawnSync(["git", "init", directory], { env }).exitCode).toBe(0);
    await writeFile(
      path.join(directory, "example.ts"),
      'export function greeting(name: string) { return "Hello " + name; }\n',
    );
    await writeFile(path.join(directory, ".gitignore"), "ignored.ts\n");
    await writeFile(
      path.join(directory, "ignored.ts"),
      'export function ignoredFixture() { return "not indexed"; }\n',
    );
    const projects = new CodeGraphProjects(env, 60_000);
    const printed = Bun.spawnSync(
      [binary, "install", "--print-config", "opencode"],
      { env, cwd: directory },
    );
    expect(printed.exitCode).toBe(0);
    const generated = JSON.parse(
      printed.stdout.toString().slice(printed.stdout.toString().indexOf("{")),
    );
    // `.json()` is strict and only ever accepted this file because it happened
    // to carry no comment. Tracked JSONC here carries whole-line comments and
    // nothing else, so drop those lines the way `tests/_support/jsonc.sh`
    // does; it owns the rule and explains why the rest of a line is left
    // alone.
    const declared = JSON.parse(
      (
        await Bun.file(
          new URL("../opencode/opencode.jsonc", import.meta.url),
        ).text()
      )
        .split("\n")
        .filter((line) => !/^\s*\/\//.test(line))
        .join("\n"),
    );
    expect(declared.mcp.codegraph.command).toEqual(
      generated.mcp.codegraph.command,
    );
    expect(declared.mcp.codegraph.type).toEqual(generated.mcp.codegraph.type);
    server = Bun.spawn([binary, ...declared.mcp.codegraph.command.slice(1)], {
      env,
      cwd: directory,
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });
    stderr = new Response(server.stderr).text();
    let nextID = 0;
    const pending = new Map<number, (message: any) => void>();
    const input = server.stdin as import("bun").FileSink;
    drain = (async () => {
      let buffered = "";
      for await (const chunk of server!.stdout as ReadableStream<Uint8Array>) {
        buffered += new TextDecoder().decode(chunk);
        let boundary;
        while ((boundary = buffered.indexOf("\n")) >= 0) {
          const line = buffered.slice(0, boundary);
          buffered = buffered.slice(boundary + 1);
          if (!line.trim()) continue;
          const message = JSON.parse(line);
          pending.get(message.id)?.(message);
          pending.delete(message.id);
        }
      }
    })();
    async function request(method: string, params = {}) {
      const id = ++nextID;
      let timer: ReturnType<typeof setTimeout>;
      try {
        const response = await new Promise<any>((resolve, reject) => {
          timer = setTimeout(
            () => reject(new Error(`CodeGraph MCP timeout: ${method}`)),
            20_000,
          );
          pending.set(id, resolve);
          input.write(
            JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n",
          );
        });
        if (response.error) throw new Error(JSON.stringify(response.error));
        return response.result;
      } finally {
        clearTimeout(timer!);
      }
    }
    await request("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "dotfiles-fixture", version: "1" },
    });
    input.write(
      JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) +
        "\n",
    );
    const listing = await request("tools/list");
    expect(listing.tools.map((tool: any) => tool.name)).toEqual([
      "codegraph_explore",
    ]);
    expect(listing.tools[0].inputSchema.properties.projectPath.type).toBe(
      "string",
    );
    // OpenCode starts MCP before the first chat hook initializes this checkout.
    // A fresh checkout must expose the tool and pick up its new index live.
    const prepared = await projects.prepare(directory);
    if (!prepared.ready) throw new Error(prepared.notice);
    const args: Record<string, unknown> = { query: "greeting" };
    await projects.query(args, directory);
    const result = await request("tools/call", {
      name: "codegraph_explore",
      arguments: args,
    });
    expect(result.isError).not.toBe(true);
    expect(JSON.stringify(result.content)).toContain("example.ts");
    expect(JSON.stringify(result.content)).toContain("greeting");
    expect(JSON.stringify(result.content)).not.toContain("ignoredFixture");
  } finally {
    if (server) {
      server.kill();
      await server.exited;
    }
    await drain;
    await stderr;
    await rm(home, { recursive: true, force: true });
  }
}, 90_000);
