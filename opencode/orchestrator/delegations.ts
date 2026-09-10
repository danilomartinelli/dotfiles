import { Database } from "bun:sqlite";
import { createHash, randomUUID } from "node:crypto";
import { execFile } from "node:child_process";
import { mkdir, readFile, readlink, realpath, lstat } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import type { PluginInput } from "@opencode-ai/plugin";

const exec = promisify(execFile);
export const childRoles = [
  "coder",
  "reviewer",
  "scribe",
  "explore",
  "researcher",
] as const;
export const writerRoles = new Set(["coder", "scribe"]);
export type Route = { model: string; variant: string };
export type Routes = Record<string, Route>;
type Client = PluginInput["client"];
type State =
  | "starting"
  | "running"
  | "completed"
  | "failed"
  | "cancelled"
  | "timed_out"
  | "stopping";
export type Delegation = {
  id: string;
  root: string;
  rootDirectory: string;
  child?: string;
  messageID: string;
  role: string;
  route: Route;
  workItem: string;
  directory: string;
  ownership: string[];
  sourceVersion?: string;
  status: State;
  started: number;
  deadline: number;
  result?: string;
  notified: boolean;
  stopState?: "cancelled" | "timed_out" | "failed";
  abortAcknowledged?: boolean;
};
export type Request = {
  role: string;
  workItem: string;
  directory: string;
  ownership: string[];
  prompt: string;
  sourceVersion?: string;
  resume?: string;
};
const active = new Set<State>(["starting", "running", "stopping"]);

function data<T>(response: { data?: T; error?: unknown }, action: string): T {
  if (response.error || response.data === undefined)
    throw new Error(`${action} failed`);
  return response.data;
}

/** Resolves symlinked ancestors even when a writer is creating a new file. */
export async function canonical(filename: string, links = 0): Promise<string> {
  if (links > 40) throw new Error("Too many symbolic links in write target.");
  try {
    return await realpath(filename);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    const entry = await lstat(filename).catch(
      (failure: NodeJS.ErrnoException) => {
        if (failure.code !== "ENOENT") throw failure;
        return undefined;
      },
    );
    // A dangling symlink is still followed by writeFile; resolve its missing
    // destination instead of mistakenly treating the link itself as a new file.
    if (entry?.isSymbolicLink())
      return canonical(
        path.resolve(path.dirname(filename), await readlink(filename)),
        links + 1,
      );
    const parent = path.dirname(filename);
    if (parent === filename) throw error;
    return path.join(await canonical(parent, links), path.basename(filename));
  }
}

export function overlaps(a: string, b: string): boolean {
  return (
    a === b ||
    a.startsWith(`${b}${path.sep}`) ||
    b.startsWith(`${a}${path.sep}`)
  );
}

/** Includes unstaged, staged and untracked content; never executes diff helpers. */
export async function sourceVersion(directory: string): Promise<string> {
  const git = async (...args: string[]) =>
    (
      await exec(
        "git",
        [
          "--no-optional-locks",
          "--no-pager",
          "-c",
          "core.fsmonitor=false",
          ...args,
        ],
        {
          cwd: directory,
          timeout: 10_000,
          maxBuffer: 16 * 1024 * 1024,
          env: {
            ...process.env,
            GIT_DIR: undefined,
            GIT_WORK_TREE: undefined,
            GIT_NO_LAZY_FETCH: "1",
          },
        },
      )
    ).stdout;
  const [head, diff, untracked] = await Promise.all([
    git("rev-parse", "HEAD"),
    git("diff", "--no-ext-diff", "--no-textconv", "--binary", "HEAD", "--"),
    git("ls-files", "--others", "--exclude-standard", "-z"),
  ]);
  const hash = createHash("sha256").update(head).update(diff);
  const files = untracked.split("\0").filter(Boolean).sort();
  if (files.length > 1000)
    throw new Error(
      "Review snapshot exceeds 1000 untracked files; narrow/clean the worktree first.",
    );
  let bytes = 0;
  for (const file of files) {
    const full = path.join(directory, file);
    const info = await lstat(full);
    bytes += info.size;
    if ((!info.isFile() && !info.isSymbolicLink()) || bytes > 16 * 1024 * 1024)
      throw new Error(
        "Review snapshot contains unsupported or oversized untracked content.",
      );
    hash
      .update(file)
      .update("\0")
      .update(
        info.isSymbolicLink() ? await readlink(full) : await readFile(full),
      )
      .update("\0");
  }
  return `${head.trim()}:${hash.digest("hex")}`;
}

export class Delegations {
  private db: Database;
  onStopped?: (row: Delegation) => Promise<void>;
  private timers = new Map<string, ReturnType<typeof setTimeout>>();
  private consolidations = new Set<string>();
  constructor(
    filename: string,
    private client: Client,
    private routes: Routes,
    private timeoutMs = 15 * 60_000,
    private snapshot = sourceVersion,
  ) {
    this.db = new Database(filename, { create: true });
    this.db.exec(
      "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; CREATE TABLE IF NOT EXISTS delegations (id TEXT PRIMARY KEY, record TEXT NOT NULL)",
    );
    this.db.exec(
      "CREATE TABLE IF NOT EXISTS plans (root TEXT PRIMARY KEY, content TEXT NOT NULL)",
    );
    this.db.exec(
      "CREATE TABLE IF NOT EXISTS tool_calls (id TEXT PRIMARY KEY, child TEXT NOT NULL, generation TEXT NOT NULL)",
    );
  }

  list(root: string): Delegation[] {
    return this.all().filter((row) => row.root === root);
  }
  private all(): Delegation[] {
    return (
      this.db.query("SELECT record FROM delegations ORDER BY rowid").all() as {
        record: string;
      }[]
    ).map((row) => JSON.parse(row.record) as Delegation);
  }
  private save(row: Delegation) {
    this.db
      .query(
        "INSERT INTO delegations VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET record=excluded.record",
      )
      .run(row.id, JSON.stringify(row));
  }
  get(root: string, id: string): Delegation {
    const row = this.list(root).find((row) => row.id === id);
    if (!row) throw new Error("Delegation not found in this root session.");
    return row;
  }
  forChild(child: string): Delegation | undefined {
    return (
      this.db.query("SELECT record FROM delegations").all() as {
        record: string;
      }[]
    )
      .map((row) => JSON.parse(row.record) as Delegation)
      .find((row) => row.child === child);
  }
  savePlan(root: string, content: string) {
    this.db
      .query(
        "INSERT INTO plans VALUES (?, ?) ON CONFLICT(root) DO UPDATE SET content=excluded.content",
      )
      .run(root, content);
  }
  toolStarted(child: string, callID: string) {
    this.db
      .transaction(() => {
        const row = this.forChild(child);
        if (!row) return;
        if (!["starting", "running"].includes(row.status))
          throw new Error(
            "This delegation is stopping or terminal; no new execution may start.",
          );
        this.db
          .query("INSERT OR IGNORE INTO tool_calls VALUES (?, ?, ?)")
          .run(callID, child, row.messageID);
      })
      .immediate();
  }
  async toolFinished(child: string, callID: string) {
    this.db
      .query("DELETE FROM tool_calls WHERE id=? AND child=?")
      .run(callID, child);
    const row = this.forChild(child);
    if (row?.status === "stopping") await this.finishStop(row);
  }
  private outstanding(row: Delegation) {
    return Number(
      (
        this.db
          .query(
            "SELECT COUNT(*) AS count FROM tool_calls WHERE child=? AND generation=?",
          )
          .get(row.child ?? "", row.messageID) as { count: number }
      ).count,
    );
  }
  private async finishStop(row: Delegation) {
    if (!row.abortAcknowledged || !row.stopState || this.outstanding(row))
      return;
    const statuses = data(
      await this.client.session.status({ query: { directory: row.directory } }),
      "Confirm stopped session",
    );
    if (row.child && statuses[row.child] && statuses[row.child].type !== "idle")
      return;
    const current = this.get(row.root, row.id);
    if (
      current.messageID !== row.messageID ||
      current.status !== "stopping" ||
      this.outstanding(current)
    )
      return;
    current.status = row.stopState;
    this.save(current);
    await this.onStopped?.(current);
  }
  readPlan(root: string): string {
    return (
      (
        this.db.query("SELECT content FROM plans WHERE root=?").get(root) as {
          content: string;
        } | null
      )?.content ?? "No plan saved for this session."
    );
  }
  async assertRoot(sessionID: string) {
    const session = data(
      await this.client.session.get({ path: { id: sessionID } }),
      "Resolve root session",
    );
    if (session.parentID)
      throw new Error("Leaf sessions cannot orchestrate or capture memory.");
    return session;
  }
  assertSettled(root: string) {
    if (this.list(root).some((row) => active.has(row.status)))
      throw new Error(
        "Wait for or cancel active delegations before consolidation.",
      );
  }
  async consolidate<T>(root: string, run: () => Promise<T>): Promise<T> {
    if (this.consolidations.size)
      throw new Error("Memory consolidation is already active.");
    // SQLite releases this reservation on process death. No durable flag can
    // strand a work item after a crash or expire while a write is still active.
    this.db.exec("BEGIN IMMEDIATE");
    this.consolidations.add(root);
    try {
      this.assertSettled(root);
      const result = await run();
      this.db.exec("COMMIT");
      return result;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    } finally {
      this.consolidations.delete(root);
    }
  }
  async start(root: string, request: Request): Promise<Delegation> {
    if (this.consolidations.size)
      throw new Error(
        "Finish memory consolidation before starting another delegation.",
      );
    const rootSession = await this.assertRoot(root);
    if (
      !childRoles.includes(request.role as (typeof childRoles)[number]) ||
      !this.routes[request.role]
    )
      throw new Error(
        `Unknown delegation role: ${request.role}. Select a declared profile role.`,
      );
    if (!request.workItem.trim() || !request.prompt.trim())
      throw new Error("A work item and bounded prompt are required.");
    if (!path.isAbsolute(request.directory))
      throw new Error("Delegation directory must be absolute.");
    const directory = await realpath(request.directory);
    const ownership = await Promise.all(
      request.ownership.map((file) => canonical(path.resolve(directory, file))),
    );
    if (
      ownership.some(
        (file) =>
          !overlaps(directory, file) ||
          (file !== directory && !file.startsWith(`${directory}/`)),
      )
    )
      throw new Error(
        "File ownership must stay inside the delegation directory.",
      );
    const writer = writerRoles.has(request.role);
    const reviewer = request.role === "reviewer";
    if (writer && !ownership.length)
      throw new Error("Writers need explicit file or directory ownership.");
    if (!writer && ownership.length)
      throw new Error(
        "Read-only roles need empty ownership; put the investigation or review scope in the prompt.",
      );
    if (
      reviewer &&
      (!request.sourceVersion ||
        request.sourceVersion !== (await this.snapshot(directory)))
    )
      throw new Error(
        "Review requires a current review_snapshot source version.",
      );

    const row = this.db
      .transaction(() => {
        if (this.consolidations.size)
          throw new Error(
            "Finish memory consolidation before starting another delegation.",
          );
        const old = request.resume ? this.get(root, request.resume) : undefined;
        if (
          old &&
          (active.has(old.status) ||
            old.workItem !== request.workItem ||
            old.role !== request.role ||
            old.directory !== directory ||
            JSON.stringify(old.route) !==
              JSON.stringify(this.routes[request.role]))
        )
          throw new Error(
            "Resume requires a terminal session with the same work item, role, directory and declared route.",
          );
        const running = this.all().filter((item) => active.has(item.status));
        if (running.filter((item) => item.root === root).length >= 3)
          throw new Error(
            "Three delegations are already active; wait or cancel before starting another.",
          );
        for (const item of running) {
          if (
            overlaps(directory, item.directory) &&
            ((writer && item.sourceVersion) ||
              (reviewer && item.ownership.length > 0))
          )
            throw new Error("Review a stable version after writers finish.");
          if (
            writer &&
            item.ownership.length > 0 &&
            ownership.some((a) => item.ownership.some((b) => overlaps(a, b)))
          )
            throw new Error(
              `Writer ownership overlaps delegation ${item.id}; resume it after completion or serialize the change.`,
            );
        }
        const next: Delegation = {
          id: old?.id ?? randomUUID(),
          child: old?.child,
          root,
          rootDirectory: rootSession.directory,
          role: request.role,
          messageID: `msg_${Date.now().toString(16)}${randomUUID().replaceAll("-", "")}`,
          route: { ...this.routes[request.role] },
          workItem: request.workItem,
          directory,
          ownership,
          sourceVersion: request.sourceVersion,
          status: "starting",
          started: Date.now(),
          deadline: Date.now() + this.timeoutMs,
          notified: false,
        };
        this.save(next);
        return next;
      })
      .immediate();

    try {
      if (!row.child) {
        const child = data(
          await this.client.session.create({
            query: { directory },
            body: {
              parentID: root,
              title: `${row.role}: ${row.workItem.slice(0, 70)} [${row.id}]`,
            },
          }),
          "Create delegation",
        ).id;
        const current = this.get(root, row.id);
        current.child = child;
        this.save(current);
        row.child = child;
        if (current.status !== "starting") return this.stop(root, row.id);
      }
      const [providerID, ...modelID] = row.route.model.split("/");
      const body = {
        messageID: row.messageID,
        agent: row.role,
        model: { providerID, modelID: modelID.join("/") },
        variant: row.route.variant,
        tools: {
          task: false,
          delegate: false,
          delegation_cancel: false,
          memory_commit: false,
          plan_save: false,
        },
        parts: [
          {
            type: "text" as const,
            text: [
              `Work item: ${row.workItem}. Directory: ${directory}.`,
              `Declared route: ${row.role} = ${row.route.model}/${row.route.variant}.`,
              `File ownership: ${ownership.join(", ") || "read-only"}.`,
              row.sourceVersion
                ? `Review source version: ${row.sourceVersion}.`
                : "",
              request.prompt,
            ]
              .filter(Boolean)
              .join("\n"),
          },
        ],
      };
      const response = await this.client.session.promptAsync({
        path: { id: row.child },
        query: { directory },
        body,
      });
      if (response.error) throw new Error("Delegation prompt was rejected.");
      // An idle event can arrive before prompt_async returns; never overwrite it.
      const current = this.get(root, row.id);
      if (
        current.messageID === row.messageID &&
        current.status === "starting"
      ) {
        current.status = "running";
        this.save(current);
      }
      this.arm(current);
      return current;
    } catch (error) {
      row.result = String(error);
      // An ambiguous transport failure may have accepted the prompt. Abort it.
      if (row.child) await this.stop(root, row.id, "failed", row.result);
      else {
        row.status = "failed";
        this.save(row);
      }
      throw error;
    }
  }

  private arm(row: Delegation) {
    if (!active.has(row.status) || this.timers.has(row.id)) return;
    const timer = setTimeout(
      () => {
        this.timers.delete(row.id);
        if (this.get(row.root, row.id).messageID !== row.messageID) return;
        void this.stop(
          row.root,
          row.id,
          "timed_out",
          "Delegation exceeded its deadline.",
        ).catch(() => {});
      },
      Math.max(1, row.deadline - Date.now()),
    );
    timer.unref();
    this.timers.set(row.id, timer);
  }

  async stop(
    root: string,
    id: string,
    state: "cancelled" | "timed_out" | "failed" = "cancelled",
    reason = "Cancelled by orchestrator.",
  ) {
    if (this.consolidations.size)
      throw new Error(
        "Memory consolidation is holding the project lifecycle reservation.",
      );
    const row = this.get(root, id);
    if (!active.has(row.status)) return row;
    row.status = "stopping";
    row.stopState = state;
    row.abortAcknowledged = false;
    row.result = reason;
    this.save(row);
    try {
      if (!row.child)
        throw new Error(
          "Child creation was interrupted; reconcile session list before retrying this work item.",
        );
      const target = data(
        await this.client.session.get({
          path: { id: row.child },
          query: { directory: row.directory },
        }),
        "Resolve cancellation target",
      );
      if (
        target.parentID !== row.root ||
        (await realpath(target.directory)) !== row.directory
      )
        throw new Error(
          "Cancellation target does not match this delegation's root and directory.",
        );
      const response = await this.client.session.abort({
        path: { id: row.child },
        query: { directory: row.directory },
      });
      if (response.error || response.data !== true)
        throw new Error("Execution abort was not acknowledged.");
      row.abortAcknowledged = true;
      row.result = `${reason} Abort acknowledged; waiting for native tool completion acknowledgments.`;
    } catch (error) {
      row.result = `${reason} ${error}`;
    }
    const current = this.get(root, id);
    if (current.messageID === row.messageID && current.status === "stopping")
      this.save(row);
    clearTimeout(this.timers.get(id));
    this.timers.delete(id);
    await this.finishStop(this.get(root, id));
    return this.get(root, id);
  }

  async complete(child: string) {
    if (this.consolidations.size) return;
    const all = (
      this.db.query("SELECT record FROM delegations").all() as {
        record: string;
      }[]
    ).map((value) => JSON.parse(value.record) as Delegation);
    const row = all.find(
      (value) => value.child === child && active.has(value.status),
    );
    if (!row) return;
    if (row.status === "stopping") {
      await this.finishStop(row);
      return;
    }
    const messages = data(
      await this.client.session.messages({
        path: { id: child },
        query: { directory: row.directory },
      }),
      "Read delegation result",
    );
    const last = messages.at(-1);
    // A genuine tool error is emitted after its execution rejects. The core's
    // forced `interrupted` placeholder is not evidence that its process ended.
    for (const message of messages)
      for (const part of message.parts) {
        if (
          part.type === "tool" &&
          part.state.status === "error" &&
          !part.state.metadata?.interrupted
        )
          this.db
            .query(
              "DELETE FROM tool_calls WHERE id=? AND child=? AND generation=?",
            )
            .run(part.callID, child, row.messageID);
      }
    if (this.outstanding(row)) return;
    const promptIndex = messages.findIndex(
      (message) =>
        message.info.id === row.messageID && message.info.role === "user",
    );
    // Native compaction can append a synthetic continuation user. The original
    // generation must exist before the final assistant; a previous run cannot finish it.
    if (
      promptIndex < 0 ||
      promptIndex === messages.length - 1 ||
      !last ||
      last.info.role !== "assistant" ||
      !last.info.time.completed
    )
      return;
    if (
      !last.info.error &&
      (!last.info.finish ||
        ["tool-calls", "unknown"].includes(last.info.finish) ||
        last.parts.some(
          (part) =>
            part.type === "tool" &&
            ["pending", "running"].includes(part.state.status),
        ))
    )
      return;
    row.result = last.parts
      .filter((part) => part.type === "text")
      .map((part) => ("text" in part ? part.text : ""))
      .join("\n");
    row.status = last.info.error ? "failed" : "completed";
    if (last.info.error) row.result = JSON.stringify(last.info.error);
    if (
      row.sourceVersion &&
      row.sourceVersion !== (await this.snapshot(row.directory))
    ) {
      row.status = "failed";
      row.result = `Review source changed during execution; verdict is stale.\n${row.result}`;
    }
    this.db
      .transaction(() => {
        const current = this.get(row.root, row.id);
        if (
          current.messageID === row.messageID &&
          ["starting", "running"].includes(current.status)
        )
          this.save(row);
      })
      .immediate();
    if (this.get(row.root, row.id).messageID === row.messageID) {
      clearTimeout(this.timers.get(row.id));
      this.timers.delete(row.id);
    }
  }

  /** Idempotent recovery: inspect existing children, never create replacements. */
  async recover(root: string) {
    for (const row of this.list(root).filter((item) =>
      active.has(item.status),
    )) {
      if (row.child) await this.complete(row.child);
      const current = this.get(root, row.id);
      if (active.has(current.status) && Date.now() >= current.deadline)
        await this.stop(
          root,
          row.id,
          "timed_out",
          "Deadline elapsed while the orchestrator was disconnected.",
        );
      else this.arm(current);
    }
  }
  notifications(root: string): string[] {
    return this.db
      .transaction(() =>
        this.list(root)
          .filter((row) => !active.has(row.status) && !row.notified)
          .map((row) => {
            row.notified = true;
            this.save(row);
            return `${row.id}: ${row.role} ${row.status} (${row.route.model}/${row.route.variant}); use delegation_read for evidence.`;
          }),
      )
      .immediate();
  }
  restoreNotifications(root: string, notices: string[]) {
    this.db
      .transaction(() => {
        for (const notice of notices) {
          const row = this.get(root, notice.split(":", 1)[0]);
          if (!active.has(row.status)) {
            row.notified = false;
            this.save(row);
          }
        }
      })
      .immediate();
  }
  close() {
    for (const timer of this.timers.values()) clearTimeout(timer);
    this.db.close();
  }
}

export async function openDelegations(
  directory: string,
  client: Client,
  routes: Routes,
) {
  await mkdir(path.dirname(directory), { recursive: true });
  return new Delegations(directory, client, routes);
}
