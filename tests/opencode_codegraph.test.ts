import { expect, test } from "bun:test";
import {
  mkdtemp,
  mkdir,
  realpath,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { CodeGraphProjects } from "../opencode/orchestrator/codegraph";

async function fixture() {
  const home = await realpath(
    await mkdtemp(path.join(tmpdir(), "opencode-codegraph-")),
  );
  const directory = path.join(home, "repository");
  const bin = path.join(home, "bin");
  const log = path.join(home, "init.log");
  await mkdir(directory);
  await mkdir(bin);
  const env = {
    HOME: home,
    PATH: `${bin}:${process.env.PATH}`,
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    CODEGRAPH_INIT_LOG: log,
  };
  await writeFile(
    path.join(bin, "codegraph"),
    `#!/bin/sh
set -eu
[ "$1" = init ]
[ "$CODEGRAPH_TELEMETRY" = 0 ]
printf '%s\\n' "$2" >> "$CODEGRAPH_INIT_LOG"
exit_code=\${FAIL_CODEGRAPH_INIT:-0}
[ "$exit_code" = 0 ] || exit "$exit_code"
sleep 0.1
printf 'fixture database' > "$2/.codegraph/codegraph.db"
`,
    { mode: 0o755 },
  );
  function git(...args: string[]) {
    const result = Bun.spawnSync(
      ["git", "-c", "core.fsmonitor=false", "-C", directory, ...args],
      { env },
    );
    if (result.exitCode !== 0) throw new Error(result.stderr.toString());
    return result.stdout.toString().trim();
  }
  git("init");
  git(
    "-c",
    "user.name=Fixture",
    "-c",
    "user.email=fixture@example.invalid",
    "commit",
    "--allow-empty",
    "-m",
    "Fixture",
  );
  return {
    home,
    directory,
    bin,
    log,
    env,
    git,
    cleanup: () => rm(home, { recursive: true, force: true }),
  };
}

test("concurrent sessions initialize once at the Git root and preserve existing ignore content", async () => {
  const f = await fixture();
  try {
    await mkdir(path.join(f.directory, "packages/app"), { recursive: true });
    await writeFile(
      path.join(f.directory, ".gitignore"),
      "existing-local-file",
    );
    const projects = new CodeGraphProjects(f.env);
    const results = await Promise.all([
      projects.prepare(f.directory),
      projects.prepare(path.join(f.directory, "packages/app")),
      new CodeGraphProjects(f.env).prepare(f.directory),
    ]);
    expect(results.every((result) => result.ready)).toBe(true);
    expect(await Bun.file(f.log).text()).toBe(`${f.directory}\n`);
    expect(await Bun.file(path.join(f.directory, ".gitignore")).text()).toBe(
      "existing-local-file\n/.codegraph/\n",
    );
    expect(f.git("check-ignore", ".codegraph/.gitignore")).toBe(
      ".codegraph/.gitignore",
    );
    const query: Record<string, unknown> = {
      query: "Example",
      projectPath: "packages/app",
    };
    await projects.query(query, f.directory);
    expect(query.projectPath).toBe(f.directory);
    await expect(
      projects.query({ projectPath: f.home }, f.directory),
    ).rejects.toThrow("session's Git checkout");
  } finally {
    await f.cleanup();
  }
});

test("a global Git ignore needs no project edit and existing indices never run init", async () => {
  const f = await fixture();
  try {
    const globalIgnore = path.join(f.home, "ignore");
    await writeFile(globalIgnore, ".codegraph/\n");
    f.git("config", "core.excludesFile", globalIgnore);
    await mkdir(path.join(f.directory, ".codegraph"));
    await writeFile(
      path.join(f.directory, ".codegraph/codegraph.db"),
      "existing",
    );
    expect(
      (await new CodeGraphProjects(f.env).prepare(f.directory)).ready,
    ).toBe(true);
    expect(await Bun.file(path.join(f.directory, ".gitignore")).exists()).toBe(
      false,
    );
    expect(await Bun.file(f.log).exists()).toBe(false);
    expect(
      await Bun.file(path.join(f.directory, ".codegraph/codegraph.db")).text(),
    ).toBe("existing");
  } finally {
    await f.cleanup();
  }
});

test("separate OpenCode processes cannot initialize the same checkout twice", async () => {
  const f = await fixture();
  try {
    const script = path.join(f.home, "prepare.ts");
    const owner = new URL(
      "../opencode/orchestrator/codegraph.ts",
      import.meta.url,
    ).pathname;
    await writeFile(
      script,
      `import { CodeGraphProjects } from ${JSON.stringify(owner)}; await new CodeGraphProjects().prepare(process.argv[2]);`,
    );
    const children = Array.from({ length: 3 }, () =>
      Bun.spawn([process.execPath, script, f.directory], {
        env: f.env,
        stdout: "ignore",
        stderr: "pipe",
      }),
    );
    expect(await Promise.all(children.map((child) => child.exited))).toEqual([
      0, 0, 0,
    ]);
    expect(await Bun.file(f.log).text()).toBe(`${f.directory}\n`);
    expect(await Bun.file(path.join(f.directory, ".gitignore")).text()).toBe(
      "/.codegraph/\n",
    );
  } finally {
    await f.cleanup();
  }
});

test("a missing CLI reports the dependency without creating project files", async () => {
  const f = await fixture();
  try {
    const prepared = await new CodeGraphProjects({
      ...f.env,
      PATH: "/usr/bin:/bin",
    }).prepare(f.directory);
    expect(prepared.ready).toBe(false);
    expect(prepared.notice).toContain("CLI is missing");
    expect(await Bun.file(path.join(f.directory, ".gitignore")).exists()).toBe(
      false,
    );
    await expect(
      realpath(path.join(f.directory, ".codegraph")),
    ).rejects.toThrow();
  } finally {
    await f.cleanup();
  }
});

test("linked worktrees get their own index and queries cannot select the main checkout", async () => {
  const f = await fixture();
  try {
    const worktree = path.join(f.home, "worktree");
    f.git("worktree", "add", "--detach", worktree);
    const projects = new CodeGraphProjects(f.env);
    expect((await projects.prepare(worktree)).root).toBe(worktree);
    expect(await Bun.file(f.log).text()).toBe(`${worktree}\n`);
    expect(await Bun.file(path.join(f.directory, ".gitignore")).exists()).toBe(
      false,
    );
    await expect(
      projects.query({ projectPath: f.directory }, worktree),
    ).rejects.toThrow("session's Git checkout");
  } finally {
    await f.cleanup();
  }
});

test("non-Git directories and a Git home directory do not trigger indexing", async () => {
  const f = await fixture();
  try {
    const projects = new CodeGraphProjects(f.env);
    expect((await projects.prepare(f.home)).ready).toBe(false);
    Bun.spawnSync(["git", "init", f.home], { env: f.env });
    expect((await projects.prepare(f.home)).ready).toBe(false);
    expect(await Bun.file(f.log).exists()).toBe(false);
    expect(await Bun.file(path.join(f.home, ".gitignore")).exists()).toBe(
      false,
    );
  } finally {
    await f.cleanup();
  }
});

test("failed initialization is reported once without retries or deleting its partial index", async () => {
  const f = await fixture();
  try {
    const projects = new CodeGraphProjects({
      ...f.env,
      FAIL_CODEGRAPH_INIT: "9",
    });
    const first = await projects.prepare(f.directory);
    expect(first.ready).toBe(false);
    expect(first.notice).toContain("automatic initialization will not retry");
    expect(await projects.prepare(f.directory)).toEqual(first);
    await expect(
      projects.query({ query: "Example" }, f.directory),
    ).rejects.toThrow("CodeGraph unavailable");
    expect(await Bun.file(f.log).text()).toBe(`${f.directory}\n`);
    expect(await realpath(path.join(f.directory, ".codegraph"))).toBe(
      path.join(f.directory, ".codegraph"),
    );
  } finally {
    await f.cleanup();
  }
});

test.each(["index symlink", "ignore symlink", "tracked index", "empty index"])(
  "preserves %s without indexing or untracking files",
  async (kind) => {
    const f = await fixture();
    try {
      const index = path.join(f.directory, ".codegraph");
      const outside = path.join(f.home, "outside");
      await writeFile(outside, "preserve me");
      if (kind === "index symlink") await symlink(f.home, index);
      else if (kind === "ignore symlink")
        await symlink(outside, path.join(f.directory, ".gitignore"));
      else {
        await mkdir(index);
        if (kind === "tracked index") {
          await writeFile(path.join(index, "codegraph.db"), "tracked");
          f.git("add", ".codegraph");
        }
      }
      expect(
        (await new CodeGraphProjects(f.env).prepare(f.directory)).ready,
      ).toBe(false);
      expect(await Bun.file(outside).text()).toBe("preserve me");
      expect(await Bun.file(f.log).exists()).toBe(false);
      if (kind === "tracked index")
        expect(f.git("ls-files", ".codegraph")).toBe(".codegraph/codegraph.db");
    } finally {
      await f.cleanup();
    }
  },
);
