import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { MemoryStorage, Transaction } from "./store.ts";

export const MEMORY_BASELINE_VERSION = "2.25.0";

/** The private storage seam is intentionally version-checked before any import with side effects. */
export async function loadMemoryBaseline(
  entrypoint = fileURLToPath(import.meta.resolve("opencode-mem")),
) {
  const packageRoot = dirname(dirname(entrypoint));
  const manifest = JSON.parse(
    await readFile(join(packageRoot, "package.json"), "utf8"),
  );
  if (
    manifest.name !== "opencode-mem" ||
    manifest.version !== MEMORY_BASELINE_VERSION
  ) {
    throw new Error(
      `The memory adapter requires opencode-mem ${MEMORY_BASELINE_VERSION}`,
    );
  }
  const moduleAt = (relative: string) =>
    import(pathToFileURL(join(packageRoot, relative)).href);
  const plugin = await moduleAt("dist/plugin.js");
  return {
    plugin: plugin.OpenCodeMemPlugin,
    async storage(directory: string): Promise<MemoryStorage> {
      const [
        ready,
        embedding,
        tags,
        scope,
        shards,
        connections,
        vectors,
        config,
        operations,
      ] = await Promise.all([
        moduleAt("dist/services/turso/ready.js"),
        moduleAt("dist/services/embedding.js"),
        moduleAt("dist/services/tags.js"),
        moduleAt("dist/services/memory-scope.js"),
        moduleAt("dist/services/turso/shard-manager.js"),
        moduleAt("dist/services/turso/connection-manager.js"),
        moduleAt("dist/services/turso/vector-search.js"),
        moduleAt("dist/config.js"),
        moduleAt("dist/services/turso/operation-lock.js"),
      ]);
      await ready.ensureTursoReady();
      const project = tags.getProjectTagInfo(directory).tag;
      const { hash } = scope.extractScopeFromContainerTag(project);
      const manager = shards.tursoShardManager;
      let stableShard: { id: number; dbPath: string; shardIndex: number };
      await manager.withScopeWriteLock("project", hash, async () => {
        operations.assertNoTursoMigrationInProgress();
        let roster = await manager.getAllShards("project", hash);
        if (roster.length === 0) {
          await manager.getWriteShard("project", hash);
          roster = await manager.getAllShards("project", hash);
        }
        stableShard = roster.sort(
          (a: { shardIndex: number }, b: { shardIndex: number }) =>
            a.shardIndex - b.shardIndex,
        )[0];
        if (
          !stableShard ||
          stableShard.shardIndex !== 0 ||
          !existsSync(stableShard.dbPath)
        ) {
          throw new Error(
            "The stable project memory shard is missing; restore it before writing",
          );
        }
      });
      const db = await connections.tursoConnectionManager.getConnection(
        stableShard!.dbPath,
      );
      const dimensions = await db.get(
        "SELECT value FROM shard_metadata WHERE key = 'embedding_dimensions'",
      );
      if (Number(dimensions?.value) !== config.CONFIG.embeddingDimensions) {
        throw new Error(
          "The stable memory shard uses incompatible embeddings; migrate it before writing",
        );
      }
      return {
        project,
        directory,
        capacity: config.CONFIG.maxVectorsPerShard,
        withWriteLock: (run) =>
          manager.withScopeWriteLock("project", hash, async () => {
            operations.assertNoTursoMigrationInProgress();
            return run();
          }),
        transaction: (run) => db.transaction("write", run),
        embed: (content) =>
          embedding.embeddingService.embedWithTimeout(content, {
            task: "document",
          }),
        insert: (tx: Transaction, record) =>
          vectors.tursoVectorSearch.insertVectorInTransaction(tx, record),
        async syncCount() {
          const count = await db.get("SELECT COUNT(*) AS count FROM memories");
          await manager.setVectorCount(stableShard!.id, Number(count.count));
        },
      };
    },
  };
}
