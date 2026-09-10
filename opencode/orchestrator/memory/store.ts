import { createHash } from "node:crypto";

export type SqlValue = string | number | null;
export type Row = Record<string, unknown>;
export interface Transaction {
  execute(statement: {
    sql: string;
    args?: SqlValue[];
  }): Promise<{ rows: Row[] }>;
}

export interface MemoryRecord {
  id: string;
  content: string;
  vector: Float32Array;
  containerTag: string;
  tags?: string;
  type: string;
  createdAt: number;
  updatedAt: number;
  metadata: string;
  projectPath: string;
}

export interface MemoryStorage {
  project: string;
  directory: string;
  capacity: number;
  withWriteLock<T>(run: () => Promise<T>): Promise<T>;
  transaction<T>(run: (tx: Transaction) => Promise<T>): Promise<T>;
  embed(content: string): Promise<Float32Array>;
  insert(tx: Transaction, record: MemoryRecord): Promise<void>;
  syncCount(): Promise<void>;
}

export interface MemoryOutcome {
  project: string;
  workItem: string;
  outcome: string;
  summary: string;
  evidence: string[];
  tags?: string[];
}

function boundedText(value: unknown, name: string, limit: number): string {
  if (typeof value !== "string" || !value.trim() || value.length > limit) {
    throw new Error(`${name} must be nonempty and at most ${limit} characters`);
  }
  if (/<\/?private\b/i.test(value)) {
    throw new Error(
      `${name} contains private markup; submit only durable public evidence`,
    );
  }
  return value.trim();
}

function normalizeOutcome(input: MemoryOutcome): Required<MemoryOutcome> {
  if (
    !Array.isArray(input.evidence) ||
    input.evidence.length < 1 ||
    input.evidence.length > 20
  ) {
    throw new Error("Supply between one and twenty evidence references");
  }
  if (
    input.tags !== undefined &&
    (!Array.isArray(input.tags) || input.tags.length > 8)
  ) {
    throw new Error("Supply at most eight tags");
  }
  return {
    project: boundedText(input.project, "project", 128),
    workItem: boundedText(input.workItem, "workItem", 256),
    outcome: boundedText(input.outcome, "outcome", 256),
    summary: boundedText(input.summary, "summary", 6000),
    evidence: [
      ...new Set(
        input.evidence.map((item) => boundedText(item, "evidence", 1000)),
      ),
    ].sort(),
    tags: [
      ...new Set(
        (input.tags ?? []).map((tag) =>
          boundedText(tag, "tag", 64).toLowerCase(),
        ),
      ),
    ].sort(),
  };
}

function hash(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function verifyExisting(row: Row, fingerprint: string, content: string): void {
  let metadata: { orchestrator?: { fingerprint?: string } };
  try {
    metadata = JSON.parse(String(row.metadata));
  } catch {
    throw new Error("Outcome identity already exists with invalid metadata");
  }
  if (
    metadata.orchestrator?.fingerprint !== fingerprint ||
    row.content !== content
  ) {
    throw new Error(
      "Outcome identity already exists with different evidence or content; use a new outcome identity",
    );
  }
}

/** Identity, evidence and content live in one existing memories row and one transaction. */
export async function commitMemoryOutcome(
  storage: MemoryStorage,
  input: MemoryOutcome,
  sessionID: string,
) {
  if (!Number.isSafeInteger(storage.capacity) || storage.capacity < 1) {
    throw new Error("Memory shard capacity must be a positive integer");
  }
  const outcome = normalizeOutcome(input);
  if (outcome.project !== storage.project) {
    throw new Error("Memory project does not match the current project");
  }
  boundedText(sessionID, "sessionID", 256);
  const id = `mem_orchestrator_${hash(JSON.stringify([outcome.project, outcome.workItem, outcome.outcome]))}`;
  const fingerprint = hash(JSON.stringify(outcome));
  const content = `${outcome.summary}\n\nEvidence:\n${outcome.evidence.map((item) => `- ${item}`).join("\n")}`;
  return storage.withWriteLock(async () => {
    // Embeddings are local and outside the write transaction. Concurrent writers
    // still arbitrate the identity under SQLite's write transaction below.
    const vector = await storage.embed(content);
    const created = await storage.transaction(async (tx) => {
      const existing = await tx.execute({
        sql: "SELECT content, metadata FROM memories WHERE id = ?",
        args: [id],
      });
      if (existing.rows[0]) {
        verifyExisting(existing.rows[0], fingerprint, content);
        return false;
      }
      const count = await tx.execute({
        sql: "SELECT COUNT(*) AS count FROM memories",
      });
      if (Number(count.rows[0]?.count) >= storage.capacity) {
        throw new Error(
          "The stable project memory shard is full; review its capacity before committing another outcome",
        );
      }
      const now = Date.now();
      await storage.insert(tx, {
        id,
        content,
        vector,
        containerTag: storage.project,
        tags: outcome.tags.join(","),
        type: "orchestrator-outcome",
        createdAt: now,
        updatedAt: now,
        projectPath: storage.directory,
        metadata: JSON.stringify({
          source: "orchestrator",
          sessionID,
          orchestrator: { version: 1, fingerprint, ...outcome },
        }),
      });
      return true;
    });
    // Upstream treats the registry count as repairable metadata. Retry repairs
    // it even when the memory transaction committed before a prior count error.
    await storage.syncCount();
    return {
      id,
      created,
      project: outcome.project,
      workItem: outcome.workItem,
      outcome: outcome.outcome,
    };
  });
}
