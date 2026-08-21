/**
 * Durable state for OCX-managed OpenCode workspaces.
 *
 * A session, branch, path, and native workspace ID form one exclusive lease.
 * Pending continuation and deletion operations are keyed by session so
 * concurrent orchestrators cannot overwrite each other's lifecycle state.
 */

import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { z } from "zod";
import { getProjectId } from "../kdco-primitives";
import { isSafeStorageSegment } from "../kdco-primitives/storage-id";

export interface Session {
	id: string;
	branch: string;
	path: string;
	createdAt: string;
	workspaceId: string | null;
}

export type SessionInput = Omit<Session, "workspaceId"> & {
	workspaceId?: string | null;
};

export interface PendingContinuation {
	sessionId: string;
	workspaceId: string;
	createdAt: string;
}

export interface ClaimedContinuation extends PendingContinuation {
	claimToken: string;
}

export interface PendingDelete {
	branch: string;
	path: string;
	sessionId: string;
	createdAt: string;
}

const sessionSchema = z.object({
	id: z.string().refine(isSafeStorageSegment, "Invalid session ID"),
	branch: z.string().min(1),
	path: z.string().min(1),
	createdAt: z.string().min(1),
	workspaceId: z.string().min(1).nullable().optional(),
});

const pendingContinuationSchema = z.object({
	sessionId: z.string().refine(isSafeStorageSegment, "Invalid session ID"),
	workspaceId: z.string().min(1),
	createdAt: z.string().min(1),
});

const pendingDeleteSchema = z.object({
	branch: z.string().min(1),
	path: z.string().min(1),
	sessionId: z.string().refine(isSafeStorageSegment, "Invalid session ID"),
	createdAt: z.string().min(1),
});

function getRuntimeHomeDirectory(): string {
	const configuredHome = process.env.HOME?.trim();
	return configuredHome && path.isAbsolute(configuredHome)
		? configuredHome
		: os.homedir();
}

function getWorktreeBaseDirectory(): string {
	return path.join(
		getRuntimeHomeDirectory(),
		".local",
		"share",
		"opencode",
		"worktree",
	);
}

export async function getWorktreePath(
	projectRoot: string,
	branch: string,
	basePath?: string,
	projectIdOverride?: string,
): Promise<string> {
	if (!branch || typeof branch !== "string")
		throw new Error("branch is required");
	const projectId = await resolveStateProjectId(projectRoot, projectIdOverride);
	const baseDirectory = basePath ?? getWorktreeBaseDirectory();
	if (!path.isAbsolute(baseDirectory)) {
		throw new Error("worktree base path must be absolute");
	}
	const projectDirectory = path.resolve(baseDirectory, projectId);
	const worktreePath = path.resolve(projectDirectory, branch);
	const relative = path.relative(projectDirectory, worktreePath);
	if (
		relative === "" ||
		relative.startsWith("..") ||
		path.isAbsolute(relative)
	) {
		throw new Error("branch escapes the project worktree directory");
	}
	return worktreePath;
}

function getDbDirectory(): string {
	return path.join(
		getRuntimeHomeDirectory(),
		".local",
		"share",
		"opencode",
		"plugins",
		"worktree",
	);
}

async function resolveStateProjectId(
	projectRoot: string,
	projectIdOverride?: string,
): Promise<string> {
	if (!projectIdOverride) return getProjectId(projectRoot);
	if (!isSafeStorageSegment(projectIdOverride)) {
		throw new Error("invalid native project ID");
	}
	return projectIdOverride;
}

async function getDbPath(
	projectRoot: string,
	projectIdOverride?: string,
): Promise<string> {
	const projectId = await resolveStateProjectId(projectRoot, projectIdOverride);
	return path.join(getDbDirectory(), `${projectId}.sqlite`);
}

function tableExists(db: Database, tableName: string): boolean {
	const row = db
		.prepare(
			"SELECT name FROM sqlite_master WHERE type = 'table' AND name = $name",
		)
		.get({ $name: tableName }) as { name?: string } | null;
	return row?.name === tableName;
}

function ensureWorkspaceIdColumn(db: Database): void {
	const columns = db.prepare("PRAGMA table_info(sessions)").all() as Array<{
		name?: string;
	}>;
	if (columns.some((column) => column.name === "workspace_id")) return;
	db.exec("ALTER TABLE sessions ADD COLUMN workspace_id TEXT");
}

function ensurePendingContinuationClaimColumns(db: Database): void {
	const columns = db
		.prepare("PRAGMA table_info(pending_continuations)")
		.all() as Array<{
		name?: string;
	}>;
	const names = new Set(columns.map((column) => column.name));
	if (!names.has("state")) {
		db.exec(
			"ALTER TABLE pending_continuations ADD COLUMN state TEXT NOT NULL DEFAULT 'pending'",
		);
	}
	if (!names.has("claim_token")) {
		db.exec("ALTER TABLE pending_continuations ADD COLUMN claim_token TEXT");
	}
	if (!names.has("claimed_at")) {
		db.exec("ALTER TABLE pending_continuations ADD COLUMN claimed_at TEXT");
	}
}

function describeDuplicateLease(db: Database): string | null {
	for (const column of ["branch", "path", "workspace_id"] as const) {
		const where =
			column === "workspace_id" ? "WHERE workspace_id IS NOT NULL" : "";
		const row = db
			.prepare(
				`SELECT ${column} AS value, COUNT(*) AS count FROM sessions ${where} GROUP BY ${column} HAVING COUNT(*) > 1 LIMIT 1`,
			)
			.get() as { value?: string; count?: number } | null;
		if (row?.value) return `${column}=${row.value} (${row.count ?? 2} claims)`;
	}
	return null;
}

interface LegacySessionRow {
	id: string;
	branch: string;
	path: string;
	createdAt: string;
	workspaceId: string | null;
}

/**
 * Older plugin releases could persist the same logical lease twice while a
 * session was being warped into a native workspace. Those rows are safe to
 * consolidate only when both the branch and path are identical and at most
 * one native workspace ID is claimed. Every other duplicate remains an
 * explicit startup error so conflicting worktrees are never guessed away.
 */
function consolidateEquivalentDuplicateLeases(db: Database): void {
	const duplicateGroups = db
		.prepare(`
			SELECT branch, path
			FROM sessions
			GROUP BY branch, path
			HAVING COUNT(*) > 1
		`)
		.all() as Array<{ branch: string; path: string }>;

	for (const group of duplicateGroups) {
		const rows = db
			.prepare(`
				SELECT
					id,
					branch,
					path,
					created_at AS createdAt,
					workspace_id AS workspaceId
				FROM sessions
				WHERE branch = $branch AND path = $path
			`)
			.all({ $branch: group.branch, $path: group.path }) as LegacySessionRow[];
		const workspaceIds = new Set(
			rows
				.map((row) => row.workspaceId)
				.filter((workspaceId): workspaceId is string => !!workspaceId),
		);
		if (workspaceIds.size > 1) {
			throw new Error(
				`Cannot consolidate equivalent legacy leases for branch=${group.branch} path=${group.path}: multiple native workspace IDs are claimed.`,
			);
		}

		const survivor = [...rows].sort((left, right) => {
			const workspacePreference =
				Number(!!right.workspaceId) - Number(!!left.workspaceId);
			if (workspacePreference !== 0) return workspacePreference;
			const createdPreference = right.createdAt.localeCompare(left.createdAt);
			return createdPreference !== 0
				? createdPreference
				: right.id.localeCompare(left.id);
		})[0];
		if (!survivor) continue;

		const redundantIds = rows
			.map((row) => row.id)
			.filter((sessionId) => sessionId !== survivor.id);
		for (const sessionId of redundantIds) {
			const pending = db
				.prepare(`
					SELECT 'continuation' AS kind FROM pending_continuations WHERE session_id = $sessionId
					UNION ALL
					SELECT 'delete' AS kind FROM pending_deletes WHERE session_id = $sessionId
					LIMIT 1
				`)
				.get({ $sessionId: sessionId }) as { kind?: string } | null;
			if (pending?.kind) {
				throw new Error(
					`Cannot consolidate legacy lease session=${sessionId}: a pending ${pending.kind} must be resolved explicitly.`,
				);
			}
		}

		const removeRedundant = db.prepare(
			"DELETE FROM sessions WHERE id = $sessionId",
		);
		const transaction = db.transaction(() => {
			for (const sessionId of redundantIds) {
				removeRedundant.run({ $sessionId: sessionId });
			}
		});
		transaction();
	}
}

function createExclusiveLeaseIndexes(db: Database): void {
	const duplicate = describeDuplicateLease(db);
	if (duplicate) {
		throw new Error(
			`Cannot enable exclusive workspace leases while duplicate session state exists: ${duplicate}. Resolve the stale claims explicitly.`,
		);
	}

	db.exec(`
		CREATE UNIQUE INDEX IF NOT EXISTS sessions_branch_unique ON sessions(branch);
		CREATE UNIQUE INDEX IF NOT EXISTS sessions_path_unique ON sessions(path);
		CREATE UNIQUE INDEX IF NOT EXISTS sessions_workspace_unique
			ON sessions(workspace_id) WHERE workspace_id IS NOT NULL;
	`);
}

function migrateLegacyPendingOperations(db: Database): void {
	if (!tableExists(db, "pending_operations")) return;

	const legacyDelete = db
		.prepare(
			"SELECT branch, path, session_id AS sessionId FROM pending_operations WHERE type = 'delete' LIMIT 1",
		)
		.get() as { branch?: string; path?: string; sessionId?: string } | null;

	if (legacyDelete?.branch && legacyDelete.path && legacyDelete.sessionId) {
		const sessionExists = db
			.prepare("SELECT 1 AS present FROM sessions WHERE id = $sessionId")
			.get({ $sessionId: legacyDelete.sessionId }) as {
			present: number;
		} | null;
		if (sessionExists) {
			db.prepare(`
				INSERT OR IGNORE INTO pending_deletes (session_id, branch, path, created_at)
				VALUES ($sessionId, $branch, $path, $createdAt)
			`).run({
				$sessionId: legacyDelete.sessionId,
				$branch: legacyDelete.branch,
				$path: legacyDelete.path,
				$createdAt: new Date().toISOString(),
			});
		}
	}

	db.exec("DROP TABLE pending_operations");
}

export async function initStateDb(
	projectRoot: string,
	projectIdOverride?: string,
): Promise<Database> {
	if (!projectRoot || typeof projectRoot !== "string") {
		throw new Error("initStateDb requires a valid project root path");
	}

	const dbPath = await getDbPath(projectRoot, projectIdOverride);
	mkdirSync(path.dirname(dbPath), { recursive: true });
	const db = new Database(dbPath);

	db.exec("PRAGMA journal_mode=WAL");
	db.exec("PRAGMA busy_timeout=5000");
	db.exec("PRAGMA foreign_keys=ON");
	db.exec(`
		CREATE TABLE IF NOT EXISTS sessions (
			id TEXT PRIMARY KEY,
			branch TEXT NOT NULL,
			path TEXT NOT NULL,
			created_at TEXT NOT NULL,
			workspace_id TEXT
		);
	`);
	ensureWorkspaceIdColumn(db);
	db.exec(`
		CREATE TABLE IF NOT EXISTS pending_continuations (
			session_id TEXT PRIMARY KEY,
			workspace_id TEXT NOT NULL UNIQUE,
			created_at TEXT NOT NULL,
			state TEXT NOT NULL DEFAULT 'pending',
			claim_token TEXT,
			claimed_at TEXT,
			FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
		);
		CREATE TABLE IF NOT EXISTS pending_deletes (
			session_id TEXT PRIMARY KEY,
			branch TEXT NOT NULL UNIQUE,
			path TEXT NOT NULL UNIQUE,
			created_at TEXT NOT NULL,
			FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
		);
	`);
	ensurePendingContinuationClaimColumns(db);
	migrateLegacyPendingOperations(db);
	consolidateEquivalentDuplicateLeases(db);
	createExclusiveLeaseIndexes(db);
	return db;
}

function parseSessionInput(session: SessionInput): Session {
	const parsed = sessionSchema.parse(session);
	return {
		id: parsed.id,
		branch: parsed.branch,
		path: path.resolve(parsed.path),
		createdAt: parsed.createdAt,
		workspaceId: parsed.workspaceId ?? null,
	};
}

function normalizeSessionRow(row: Record<string, string | null>): Session {
	return {
		id: String(row.id),
		branch: String(row.branch),
		path: String(row.path),
		createdAt: String(row.createdAt),
		workspaceId: row.workspaceId ? String(row.workspaceId) : null,
	};
}

/** Upsert only the same session ID; branch/path/workspace conflicts fail. */
export function addSession(db: Database, session: SessionInput): void {
	const parsed = parseSessionInput(session);
	db.prepare(`
		INSERT INTO sessions (id, branch, path, created_at, workspace_id)
		VALUES ($id, $branch, $path, $createdAt, $workspaceId)
		ON CONFLICT(id) DO UPDATE SET
			branch = excluded.branch,
			path = excluded.path,
			created_at = excluded.created_at,
			workspace_id = excluded.workspace_id
	`).run({
		$id: parsed.id,
		$branch: parsed.branch,
		$path: parsed.path,
		$createdAt: parsed.createdAt,
		$workspaceId: parsed.workspaceId,
	});
}

/** Acquire a new exclusive workspace lease. */
export function claimSession(db: Database, session: SessionInput): void {
	const parsed = parseSessionInput(session);
	db.prepare(`
		INSERT INTO sessions (id, branch, path, created_at, workspace_id)
		VALUES ($id, $branch, $path, $createdAt, $workspaceId)
	`).run({
		$id: parsed.id,
		$branch: parsed.branch,
		$path: parsed.path,
		$createdAt: parsed.createdAt,
		$workspaceId: parsed.workspaceId,
	});
}

export function getSession(db: Database, sessionId: string): Session | null {
	if (!sessionId) return null;
	const row = db
		.prepare(`
			SELECT id, branch, path, created_at AS createdAt, workspace_id AS workspaceId
			FROM sessions WHERE id = $id
		`)
		.get({ $id: sessionId }) as Record<string, string | null> | null;
	return row ? normalizeSessionRow(row) : null;
}

export function getSessionByBranch(
	db: Database,
	branch: string,
): Session | null {
	if (!branch) return null;
	const row = db
		.prepare(`
			SELECT id, branch, path, created_at AS createdAt, workspace_id AS workspaceId
			FROM sessions WHERE branch = $branch
		`)
		.get({ $branch: branch }) as Record<string, string | null> | null;
	return row ? normalizeSessionRow(row) : null;
}

export function getAllSessions(db: Database): Session[] {
	const rows = db
		.prepare(`
			SELECT id, branch, path, created_at AS createdAt, workspace_id AS workspaceId
			FROM sessions ORDER BY created_at ASC
		`)
		.all() as Array<Record<string, string | null>>;
	return rows.map(normalizeSessionRow);
}

export function removeSessionById(db: Database, sessionId: string): void {
	if (!sessionId) return;
	db.prepare("DELETE FROM sessions WHERE id = $id").run({ $id: sessionId });
}

export function setPendingContinuation(
	db: Database,
	continuation: Omit<PendingContinuation, "createdAt"> & { createdAt?: string },
): void {
	const parsed = pendingContinuationSchema.parse({
		...continuation,
		createdAt: continuation.createdAt ?? new Date().toISOString(),
	});
	db.prepare(`
		INSERT INTO pending_continuations (
			session_id, workspace_id, created_at, state, claim_token, claimed_at
		)
		VALUES ($sessionId, $workspaceId, $createdAt, 'pending', NULL, NULL)
		ON CONFLICT(session_id) DO UPDATE SET
			workspace_id = excluded.workspace_id,
			created_at = excluded.created_at,
			state = 'pending',
			claim_token = NULL,
			claimed_at = NULL
	`).run({
		$sessionId: parsed.sessionId,
		$workspaceId: parsed.workspaceId,
		$createdAt: parsed.createdAt,
	});
}

export function getPendingContinuation(
	db: Database,
	sessionId: string,
): PendingContinuation | null {
	if (!sessionId) return null;
	const row = db
		.prepare(`
			SELECT session_id AS sessionId, workspace_id AS workspaceId, created_at AS createdAt
			FROM pending_continuations WHERE session_id = $sessionId
		`)
		.get({ $sessionId: sessionId }) as PendingContinuation | null;
	return row ?? null;
}

export function getAllPendingContinuations(
	db: Database,
): PendingContinuation[] {
	return db
		.prepare(`
			SELECT session_id AS sessionId, workspace_id AS workspaceId, created_at AS createdAt
			FROM pending_continuations ORDER BY created_at ASC
		`)
		.all() as PendingContinuation[];
}

/**
 * Atomically claim a continuation for delivery. A crashed dispatcher becomes
 * recoverable after the supplied stale boundary, while concurrent dispatchers
 * cannot send the same continuation at the same time.
 */
export function claimPendingContinuation(
	db: Database,
	sessionId: string,
	claimToken: string,
	staleBefore: string,
	claimedAt = new Date().toISOString(),
): ClaimedContinuation | null {
	if (!sessionId || !claimToken) return null;
	const row = db
		.prepare(`
			UPDATE pending_continuations
			SET state = 'dispatching', claim_token = $claimToken, claimed_at = $claimedAt
			WHERE session_id = $sessionId
				AND (
					state = 'pending'
					OR claimed_at IS NULL
					OR claimed_at <= $staleBefore
				)
			RETURNING
				session_id AS sessionId,
				workspace_id AS workspaceId,
				created_at AS createdAt,
				claim_token AS claimToken
		`)
		.get({
			$sessionId: sessionId,
			$claimToken: claimToken,
			$claimedAt: claimedAt,
			$staleBefore: staleBefore,
		}) as ClaimedContinuation | null;
	return row ?? null;
}

export function completePendingContinuation(
	db: Database,
	sessionId: string,
	claimToken: string,
): boolean {
	if (!sessionId || !claimToken) return false;
	const result = db
		.prepare(`
			DELETE FROM pending_continuations
			WHERE session_id = $sessionId AND claim_token = $claimToken
		`)
		.run({ $sessionId: sessionId, $claimToken: claimToken });
	return result.changes === 1;
}

export function releasePendingContinuation(
	db: Database,
	sessionId: string,
	claimToken: string,
): boolean {
	if (!sessionId || !claimToken) return false;
	const result = db
		.prepare(`
			UPDATE pending_continuations
			SET state = 'pending', claim_token = NULL, claimed_at = NULL
			WHERE session_id = $sessionId AND claim_token = $claimToken
		`)
		.run({ $sessionId: sessionId, $claimToken: claimToken });
	return result.changes === 1;
}

export function clearPendingContinuation(
	db: Database,
	sessionId: string,
): void {
	if (!sessionId) return;
	db.prepare(
		"DELETE FROM pending_continuations WHERE session_id = $sessionId",
	).run({
		$sessionId: sessionId,
	});
}

export function setPendingDelete(
	db: Database,
	del: Omit<PendingDelete, "createdAt"> & { createdAt?: string },
): void {
	const parsed = pendingDeleteSchema.parse({
		...del,
		createdAt: del.createdAt ?? new Date().toISOString(),
	});
	db.prepare(`
		INSERT INTO pending_deletes (session_id, branch, path, created_at)
		VALUES ($sessionId, $branch, $path, $createdAt)
		ON CONFLICT(session_id) DO UPDATE SET
			branch = excluded.branch,
			path = excluded.path,
			created_at = excluded.created_at
	`).run({
		$sessionId: parsed.sessionId,
		$branch: parsed.branch,
		$path: path.resolve(parsed.path),
		$createdAt: parsed.createdAt,
	});
}

export function getPendingDelete(
	db: Database,
	sessionId: string,
): PendingDelete | null {
	if (!sessionId) return null;
	const row = db
		.prepare(`
			SELECT session_id AS sessionId, branch, path, created_at AS createdAt
			FROM pending_deletes WHERE session_id = $sessionId
		`)
		.get({ $sessionId: sessionId }) as PendingDelete | null;
	return row ?? null;
}

export function getAllPendingDeletes(db: Database): PendingDelete[] {
	return db
		.prepare(`
			SELECT session_id AS sessionId, branch, path, created_at AS createdAt
			FROM pending_deletes ORDER BY created_at ASC
		`)
		.all() as PendingDelete[];
}

export function clearPendingDelete(db: Database, sessionId: string): void {
	if (!sessionId) return;
	db.prepare("DELETE FROM pending_deletes WHERE session_id = $sessionId").run({
		$sessionId: sessionId,
	});
}
