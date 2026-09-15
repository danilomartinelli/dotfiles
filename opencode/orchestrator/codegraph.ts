import { execFile } from "node:child_process";
import { constants } from "node:fs";
import { lstat, mkdir, open, realpath, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { safeGitArgv, safeGitEnv } from "./safe-git";

type Preparation = { root?: string; ready: boolean; notice: string };

// Share preparation across native sessions/plugin instances in this process.
const preparations = new Map<string, Promise<Preparation>>();

/** Fixed, user-authorized index maintenance; never an agent shell capability. */
export class CodeGraphProjects {
  private readonly env: NodeJS.ProcessEnv;

  constructor(
    env = process.env,
    private readonly timeout = 180_000,
  ) {
    // The indexer runs git itself, so it inherits the same scrubbed environment
    // rather than a second answer to the same question.
    this.env = safeGitEnv({ ...env, CODEGRAPH_TELEMETRY: "0" });
  }

  private run(command: string, args: string[], cwd: string, timeout = 10_000) {
    return new Promise<string>((resolve, reject) => {
      const child = execFile(
        command,
        args,
        {
          cwd,
          env: this.env,
          timeout,
          maxBuffer: 1024 * 1024,
        },
        (error, stdout) => (error ? reject(error) : resolve(stdout.trim())),
      );
      // No interactive installation, ignored-repository opt-in or Git hook setup.
      child.stdin?.end();
    });
  }

  private git(directory: string, ...args: string[]) {
    return this.run("git", safeGitArgv(["-C", directory, ...args]), directory);
  }

  private async root(directory: string): Promise<string | undefined> {
    try {
      const root = await realpath(
        await this.git(directory, "rev-parse", "--show-toplevel"),
      );
      if (
        root === path.parse(root).root ||
        root === (await realpath(this.env.HOME ?? os.homedir()))
      )
        return undefined;
      return root;
    } catch {
      return undefined;
    }
  }

  private async ignore(root: string) {
    try {
      await this.git(
        root,
        "check-ignore",
        "--quiet",
        "--no-index",
        "--",
        ".codegraph/",
      );
      return;
    } catch (error) {
      if ((error as { code?: unknown }).code !== 1) throw error;
    }
    const file = await open(
      path.join(root, ".gitignore"),
      constants.O_RDWR |
        constants.O_APPEND |
        constants.O_CREAT |
        constants.O_NOFOLLOW,
      0o644,
    );
    try {
      const content = await file.readFile("utf8");
      await file.writeFile(
        `${content && !content.endsWith("\n") ? "\n" : ""}/.codegraph/\n`,
      );
    } finally {
      await file.close();
    }
  }

  private async initialize(root: string): Promise<Preparation> {
    try {
      const index = path.join(root, ".codegraph");
      const existing = await lstat(index).catch(
        (error: NodeJS.ErrnoException) => {
          if (error.code !== "ENOENT") throw error;
          return undefined;
        },
      );
      if (existing && !existing.isDirectory())
        throw new Error(
          ".codegraph must be a real directory, not a file or symlink",
        );
      if (!existing && !Bun.which("codegraph", { PATH: this.env.PATH }))
        throw new Error(
          "codegraph CLI is missing from PATH; install the declared Mise tools",
        );
      // Existing tracked data is preserved and reported; an ignore cannot untrack it.
      const tracked = await this.git(root, "ls-files", "--", ".codegraph");
      if (tracked) {
        await this.ignore(root);
        throw new Error(
          ".codegraph contains tracked paths; explicit Git cleanup is needed before automatic indexing",
        );
      }
      if (!existing) {
        try {
          // mkdir is the cross-process claim. CodeGraph accepts an empty directory.
          // A crash leaves it in place for explicit repair, never an automatic retry.
          await mkdir(index);
        } catch (error) {
          if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
          return {
            root,
            ready: false,
            notice:
              "CodeGraph preparation is already claimed by another process; use file/LSP queries until it finishes.",
          };
        }
        await this.ignore(root);
        await this.run("codegraph", ["init", root], root, this.timeout);
      }
      if (!(await stat(path.join(index, "codegraph.db"))).isFile())
        throw new Error(
          ".codegraph has no database; explicit codegraph init/repair is needed",
        );
      await this.ignore(root);
      return {
        root,
        ready: true,
        notice: `CodeGraph index available in ${root}.`,
      };
    } catch (error) {
      const detail =
        error instanceof Error ? error.message.slice(-1000) : String(error);
      return {
        root,
        ready: false,
        notice: `CodeGraph unavailable in ${root}: ${detail}. Continue with file/LSP queries; automatic initialization will not retry in this process.`,
      };
    }
  }

  async prepare(directory: string): Promise<Preparation> {
    const root = await this.root(directory);
    if (!root)
      return {
        ready: false,
        notice:
          "CodeGraph initialization skipped: session is not inside a supported Git checkout.",
      };
    let pending = preparations.get(root);
    if (!pending) {
      pending = this.initialize(root);
      preparations.set(root, pending);
    }
    return pending;
  }

  async query(args: Record<string, unknown>, directory: string) {
    const root = await this.root(directory);
    if (!root)
      throw new Error(
        "CodeGraph queries require a Git checkout in this session.",
      );
    if (
      args.projectPath !== undefined &&
      (typeof args.projectPath !== "string" ||
        (await this.root(path.resolve(directory, args.projectPath))) !== root)
    )
      throw new Error(
        "CodeGraph projectPath must belong to the session's Git checkout; use a delegation in the intended checkout for another project.",
      );
    const prepared = await this.prepare(directory);
    if (!prepared.ready) throw new Error(prepared.notice);
    // Always explicit: a server rooted in the parent/main checkout cannot pick its index.
    args.projectPath = root;
  }
}
