/**
 * OCX Worktree Plugin
 *
 * Creates isolated git worktrees and binds the current OpenCode session to
 * them through the native experimental workspace lifecycle.
 *
 * Inspired by opencode-worktree-session by Felix Anhalt
 * https://github.com/felixAnhalt/opencode-worktree-session
 * License: MIT
 *
 * Rewritten for OCX with production-proven patterns.
 */

import type { Database } from "bun:sqlite";
import { randomUUID } from "node:crypto";
import { lstat, mkdir, realpath, rmdir, stat, symlink } from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import {
	type Plugin,
	tool,
	type WorkspaceAdapter,
	type WorkspaceInfo,
} from "@opencode-ai/plugin";
import type { Event } from "@opencode-ai/sdk";
import { createOpencodeClient as createOpencodeClientV2 } from "@opencode-ai/sdk/v2";

/** Logger interface for structured logging */
interface Logger {
	debug: (msg: string) => void;
	info: (msg: string) => void;
	warn: (msg: string) => void;
	error: (msg: string) => void;
}

import { type ParseError, parse as parseJsonc } from "jsonc-parser";
import { z } from "zod";

import {
	claimPendingContinuation,
	claimSession,
	clearPendingContinuation,
	clearPendingDelete,
	completePendingContinuation,
	getAllPendingContinuations,
	getAllPendingDeletes,
	getAllSessions,
	getPendingDelete,
	getSession,
	getSessionByBranch,
	getWorktreePath,
	initStateDb,
	releasePendingContinuation,
	removeSessionById,
	setPendingContinuation,
	setPendingDelete,
} from "../worktree/state";

/** Maximum retries for database initialization */
const DB_MAX_RETRIES = 3;

/** Delay between retry attempts in milliseconds */
const DB_RETRY_DELAY_MS = 100;

const WORKSPACE_ADAPTER_TYPE = "ocx-git-worktree";
const CONTINUATION_CLAIM_TIMEOUT_MS = 5 * 60 * 1000;

// =============================================================================
// TYPES & SCHEMAS
// =============================================================================

/** Result type for fallible operations */
interface OkResult<T> {
	readonly ok: true;
	readonly value: T;
}
interface ErrResult<E> {
	readonly ok: false;
	readonly error: E;
}
type Result<T, E> = OkResult<T> | ErrResult<E>;

const Result = {
	ok: <T>(value: T): OkResult<T> => ({ ok: true, value }),
	err: <E>(error: E): ErrResult<E> => ({ ok: false, error }),
};

/**
 * Git branch name validation - blocks invalid refs and shell metacharacters
 * Characters blocked: control chars (0x00-0x1f, 0x7f), ~^:?*[]\\, and shell metacharacters
 */
function isValidBranchName(name: string): boolean {
	// Check for control characters
	for (let i = 0; i < name.length; i++) {
		const code = name.charCodeAt(i);
		if (code <= 0x1f || code === 0x7f) return false;
	}
	// Check for invalid git ref characters and shell metacharacters
	if (/[~^:?*[\]\\;&|`$()]/.test(name)) return false;
	return true;
}

const branchNameSchema = z
	.string()
	.min(1, "Branch name cannot be empty")
	.refine((name) => !name.startsWith("-"), {
		message: "Branch name cannot start with '-' (prevents option injection)",
	})
	.refine((name) => !name.startsWith("/") && !name.endsWith("/"), {
		message: "Branch name cannot start or end with '/'",
	})
	.refine((name) => !name.includes("//"), {
		message: "Branch name cannot contain '//'",
	})
	.refine((name) => !name.includes("@{"), {
		message: "Branch name cannot contain '@{' (git reflog syntax)",
	})
	.refine((name) => !name.includes(".."), {
		message: "Branch name cannot contain '..'",
	})
	// biome-ignore lint/suspicious/noControlCharactersInRegex: Control character detection is intentional for security
	.refine((name) => !/[\x00-\x1f\x7f ~^:?*[\]\\]/.test(name), {
		message: "Branch name contains invalid characters",
	})
	.max(255, "Branch name too long")
	.refine(
		(name) => isValidBranchName(name),
		"Contains invalid git ref characters",
	)
	.refine(
		(name) => !name.startsWith(".") && !name.endsWith("."),
		"Cannot start or end with dot",
	)
	.refine((name) => !name.endsWith(".lock"), "Cannot end with .lock");

function parseBranchName(value: string, label: string): string {
	const result = branchNameSchema.safeParse(value);
	if (!result.success) {
		throw new Error(`${label}: ${result.error.issues[0]?.message}`);
	}
	return result.data;
}

const syncPathSchema = z
	.string()
	.min(1, "Sync path cannot be empty")
	.refine((value) => !path.isAbsolute(value), "Sync path must be relative")
	.refine((value) => !value.includes(".."), "Sync path cannot contain '..'");

/**
 * Worktree plugin configuration schema.
 * Config file: .opencode/worktree.jsonc
 */
const worktreeConfigSchema = z
	.object({
		/** Custom base path for worktree storage. Supports ~ for home directory. */
		worktreePath: z.string().min(1).optional(),
		sync: z
			.object({
				/** Files to copy from main worktree (relative paths only) */
				copyFiles: z.array(syncPathSchema).default([]),
				/** Directories to symlink from main worktree (saves disk space) */
				symlinkDirs: z.array(syncPathSchema).default([]),
			})
			.strict()
			.default(() => ({ copyFiles: [], symlinkDirs: [] })),
	})
	.strict();

type WorktreeConfig = z.infer<typeof worktreeConfigSchema>;

// =============================================================================
// ERROR TYPES
// =============================================================================

class WorktreeError extends Error {
	constructor(
		message: string,
		public readonly operation: string,
		public readonly cause?: unknown,
	) {
		super(`${operation}: ${message}`);
		this.name = "WorktreeError";
	}
}

// =============================================================================
// MODULE-LEVEL STATE
// =============================================================================

const openDatabases = new Set<Database>();
let cleanupRegistered = false;

/**
 * Register process cleanup handlers for graceful database shutdown.
 * Ensures WAL checkpoint and proper close on process termination.
 *
 * NOTE: process.once() is an EventEmitter method that never throws.
 * The boolean guard is defense-in-depth for idempotency, not error recovery.
 *
 * @param database - The database instance to clean up
 */
function registerCleanupHandlers(database: Database): void {
	openDatabases.add(database);
	if (cleanupRegistered) return;
	cleanupRegistered = true;

	const cleanup = () => {
		for (const openDatabase of openDatabases) {
			try {
				openDatabase.exec("PRAGMA wal_checkpoint(TRUNCATE)");
				openDatabase.close();
			} catch {
				// Best effort cleanup - process is exiting anyway
			}
		}
		openDatabases.clear();
	};

	process.once("SIGTERM", cleanup);
	process.once("SIGINT", cleanup);
	process.once("beforeExit", cleanup);
}

/**
 * Get the database instance, initializing if needed.
 * Includes retry logic for transient initialization failures.
 *
 * @returns Database instance
 * @throws {Error} if initialization fails after all retries
 */
async function initDb(root: string, log: Logger): Promise<Database> {
	let lastError: Error | null = null;

	for (let attempt = 1; attempt <= DB_MAX_RETRIES; attempt++) {
		try {
			const database = await initStateDb(root);
			registerCleanupHandlers(database);
			return database;
		} catch (error) {
			lastError = error instanceof Error ? error : new Error(String(error));
			log.warn(
				`Database init attempt ${attempt}/${DB_MAX_RETRIES} failed: ${lastError.message}`,
			);

			if (attempt < DB_MAX_RETRIES) {
				Bun.sleepSync(DB_RETRY_DELAY_MS);
			}
		}
	}

	throw new Error(
		`Failed to initialize database after ${DB_MAX_RETRIES} attempts: ${lastError?.message}`,
	);
}

// =============================================================================
// GIT MODULE
// =============================================================================

/**
 * Execute a git command safely using Bun.spawn with explicit array.
 * Avoids shell interpolation entirely by passing args as array.
 */
async function git(
	args: string[],
	cwd: string,
): Promise<Result<string, string>> {
	try {
		const proc = Bun.spawn(["git", ...args], {
			cwd,
			stdout: "pipe",
			stderr: "pipe",
		});
		const [stdout, stderr, exitCode] = await Promise.all([
			new Response(proc.stdout).text(),
			new Response(proc.stderr).text(),
			proc.exited,
		]);
		if (exitCode !== 0) {
			return Result.err(stderr.trim() || `git ${args[0]} failed`);
		}
		return Result.ok(stdout.trim());
	} catch (error) {
		return Result.err(error instanceof Error ? error.message : String(error));
	}
}

async function branchExists(cwd: string, branch: string): Promise<boolean> {
	const result = await git(["rev-parse", "--verify", branch], cwd);
	return result.ok;
}

interface LinkedWorktree {
	path: string;
	branch: string | null;
	prunable: boolean;
}

function parseLinkedWorktrees(output: string): LinkedWorktree[] {
	return output
		.split("\0\0")
		.map((entry) => entry.split("\0").filter(Boolean))
		.filter((fields) => fields.length > 0)
		.map((fields) => {
			const worktreeField = fields.find((field) =>
				field.startsWith("worktree "),
			);
			const branchField = fields.find((field) =>
				field.startsWith("branch refs/heads/"),
			);
			return {
				path: worktreeField?.slice("worktree ".length) ?? "",
				branch: branchField?.slice("branch refs/heads/".length) ?? null,
				prunable: fields.some(
					(field) => field === "prunable" || field.startsWith("prunable "),
				),
			};
		})
		.filter((worktree) => worktree.path.length > 0);
}

async function listLinkedWorktrees(
	repoRoot: string,
): Promise<Result<LinkedWorktree[], string>> {
	const result = await git(["worktree", "list", "--porcelain", "-z"], repoRoot);
	return result.ok ? Result.ok(parseLinkedWorktrees(result.value)) : result;
}

async function existingWorktreeForBranch(
	repoRoot: string,
	branch: string,
): Promise<Result<LinkedWorktree | null, string>> {
	const result = await listLinkedWorktrees(repoRoot);
	if (!result.ok) return result;
	return Result.ok(
		result.value.find((worktree) => worktree.branch === branch) ?? null,
	);
}

async function directoryExists(directory: string): Promise<boolean> {
	const info = await stat(directory).catch(() => null);
	return info?.isDirectory() ?? false;
}

async function pathExists(candidate: string): Promise<boolean> {
	return (await lstat(candidate).catch(() => null)) !== null;
}

async function createWorktree(
	repoRoot: string,
	branch: string,
	baseBranch?: string,
	basePath?: string,
): Promise<Result<{ path: string; reused: boolean }, string>> {
	const worktreePath = await getWorktreePath(repoRoot, branch, basePath);
	const existingResult = await existingWorktreeForBranch(repoRoot, branch);
	if (!existingResult.ok) return existingResult;
	const existing = existingResult.value;
	if (existing) {
		if (existing.prunable || !(await directoryExists(existing.path))) {
			return Result.err(
				`The branch "${branch}" has a stale worktree registration at ${existing.path}. ` +
					"Choose whether to prune/archive that registration or use a different branch; no cleanup was performed automatically.",
			);
		}
		return Result.ok({ path: existing.path, reused: true });
	}

	if (await pathExists(worktreePath)) {
		return Result.err(
			`The target path ${worktreePath} already exists but is not the registered worktree for branch "${branch}". ` +
				"Choose whether to archive/remove it or create a workspace with a different branch; nothing was overwritten.",
		);
	}

	// Ensure parent directory exists
	await mkdir(path.dirname(worktreePath), { recursive: true });

	const exists = await branchExists(repoRoot, branch);

	if (exists) {
		// Checkout existing branch into worktree
		const result = await git(
			["worktree", "add", worktreePath, branch],
			repoRoot,
		);
		return result.ok
			? Result.ok({ path: worktreePath, reused: false })
			: result;
	} else {
		// Create new branch from base
		const base = baseBranch ?? "HEAD";
		const result = await git(
			["worktree", "add", "-b", branch, worktreePath, base],
			repoRoot,
		);
		return result.ok
			? Result.ok({ path: worktreePath, reused: false })
			: result;
	}
}

async function removeWorktree(
	repoRoot: string,
	worktreePath: string,
): Promise<Result<void, string>> {
	const result = await git(
		["worktree", "remove", "--force", worktreePath],
		repoRoot,
	);
	return result.ok ? Result.ok(undefined) : Result.err(result.error);
}

// =============================================================================
// FILE SYNC MODULE
// =============================================================================

/**
 * Validate that a path is safe (no escape from base directory)
 */
function isPathSafe(filePath: string, baseDir: string, log: Logger): boolean {
	// Reject absolute paths
	if (path.isAbsolute(filePath)) {
		log.warn(`[worktree] Rejected absolute path: ${filePath}`);
		return false;
	}
	// Reject obvious path traversal
	if (filePath.includes("..")) {
		log.warn(`[worktree] Rejected path traversal: ${filePath}`);
		return false;
	}
	// Verify resolved path stays within base directory
	const resolved = path.resolve(baseDir, filePath);
	if (!resolved.startsWith(baseDir + path.sep) && resolved !== baseDir) {
		log.warn(`[worktree] Path escapes base directory: ${filePath}`);
		return false;
	}
	return true;
}

function isWithinRealRoot(
	rootRealPath: string,
	candidateRealPath: string,
): boolean {
	const relative = path.relative(rootRealPath, candidateRealPath);
	return (
		relative === "" ||
		(!!relative && !relative.startsWith("..") && !path.isAbsolute(relative))
	);
}

async function resolveExistingPathWithinRoot(
	rootDir: string,
	relativePath: string,
	log: Logger,
): Promise<string | null> {
	const rootRealPath = await realpath(rootDir).catch(() => null);
	if (!rootRealPath) {
		log.warn(`[worktree] Failed to resolve worktree root: ${rootDir}`);
		return null;
	}

	const candidatePath = path.resolve(rootDir, relativePath);
	const candidateRealPath = await realpath(candidatePath).catch(() => null);
	if (!candidateRealPath) return null;

	if (!isWithinRealRoot(rootRealPath, candidateRealPath)) {
		log.warn(
			`[worktree] Rejected path escaping worktree via symlink: ${relativePath}`,
		);
		return null;
	}

	return candidateRealPath;
}

async function ensureDirectoryWithinRoot(
	rootDir: string,
	relativeDir: string,
	log: Logger,
): Promise<string | null> {
	const rootRealPath = await realpath(rootDir).catch(() => null);
	if (!rootRealPath) {
		log.warn(`[worktree] Failed to resolve worktree root: ${rootDir}`);
		return null;
	}

	const rootPath = path.resolve(rootDir);
	const targetDir = path.resolve(rootDir, relativeDir);
	const resolvedRootRelative = path.relative(rootPath, targetDir);
	if (
		resolvedRootRelative !== "" &&
		(resolvedRootRelative.startsWith("..") ||
			path.isAbsolute(resolvedRootRelative))
	) {
		log.warn(`[worktree] Rejected path escaping worktree: ${relativeDir}`);
		return null;
	}

	const rootRelative = path.relative(rootDir, targetDir);
	const parts = rootRelative.split(path.sep).filter(Boolean);
	let cursor = rootDir;

	for (const part of parts) {
		cursor = path.join(cursor, part);
		const entry = await lstat(cursor).catch(() => null);
		if (entry?.isSymbolicLink()) {
			log.warn(`[worktree] Rejected symlinked target parent: ${relativeDir}`);
			return null;
		}
		if (entry && !entry.isDirectory()) {
			log.warn(
				`[worktree] Rejected non-directory target parent: ${relativeDir}`,
			);
			return null;
		}
		if (!entry) {
			await mkdir(cursor);
		}
	}

	const finalRealPath = await realpath(targetDir).catch(() => null);
	if (!finalRealPath || !isWithinRealRoot(rootRealPath, finalRealPath)) {
		log.warn(
			`[worktree] Rejected path escaping worktree via symlink: ${relativeDir}`,
		);
		return null;
	}

	return targetDir;
}

/**
 * Copy files from source directory to target directory.
 * Skips missing files silently (production pattern).
 */
async function copyFiles(
	sourceDir: string,
	targetDir: string,
	files: string[],
	log: Logger,
): Promise<void> {
	for (const file of files) {
		if (!isPathSafe(file, sourceDir, log)) continue;

		const sourcePath = await resolveExistingPathWithinRoot(
			sourceDir,
			file,
			log,
		);
		if (!sourcePath) continue;

		const targetPath = path.join(targetDir, file);

		try {
			const sourceFile = Bun.file(sourcePath);
			if (!(await sourceFile.exists())) {
				log.debug(`[worktree] Skipping missing file: ${file}`);
				continue;
			}

			// Ensure target directory exists
			const targetFileDir = path.dirname(targetPath);
			const targetFileRelativeDir = path.relative(targetDir, targetFileDir);
			if (
				!(await ensureDirectoryWithinRoot(
					targetDir,
					targetFileRelativeDir,
					log,
				))
			)
				continue;

			const existingTarget = await lstat(targetPath).catch(() => null);
			if (existingTarget?.isSymbolicLink()) {
				log.warn(`[worktree] Rejected symlinked target file: ${file}`);
				continue;
			}

			// Copy file
			await Bun.write(targetPath, sourceFile);
			log.info(`[worktree] Copied: ${file}`);
		} catch (error) {
			const isNotFound =
				error instanceof Error &&
				(error.message.includes("ENOENT") ||
					error.message.includes("no such file"));
			if (isNotFound) {
				log.debug(`[worktree] Skipping missing: ${file}`);
			} else {
				log.warn(`[worktree] Failed to copy ${file}: ${error}`);
			}
		}
	}
}

/**
 * Create symlinks for directories from source to target.
 * Uses absolute paths for symlink targets.
 */
async function symlinkDirs(
	sourceDir: string,
	targetDir: string,
	dirs: string[],
	log: Logger,
): Promise<void> {
	for (const dir of dirs) {
		if (!isPathSafe(dir, sourceDir, log)) continue;

		const sourcePath = await resolveExistingPathWithinRoot(sourceDir, dir, log);
		if (!sourcePath) continue;

		const targetPath = path.join(targetDir, dir);

		try {
			// Check if source directory exists
			const fileStat = await stat(sourcePath).catch(() => null);
			if (!fileStat?.isDirectory()) {
				log.debug(`[worktree] Skipping missing directory: ${dir}`);
				continue;
			}

			// Ensure parent directory exists
			const targetParentDir = path.dirname(targetPath);
			const targetParentRelativeDir = path.relative(targetDir, targetParentDir);
			if (
				!(await ensureDirectoryWithinRoot(
					targetDir,
					targetParentRelativeDir,
					log,
				))
			)
				continue;

			const existingTarget = await lstat(targetPath).catch(() => null);
			if (existingTarget?.isSymbolicLink()) {
				log.warn(`[worktree] Rejected symlinked target: ${dir}`);
				continue;
			}
			if (existingTarget && !existingTarget.isDirectory()) {
				log.warn(`[worktree] Rejected non-directory target: ${dir}`);
				continue;
			}

			// rmdir is intentionally non-recursive: it atomically refuses to remove
			// a target that gained content after inspection.
			if (existingTarget) await rmdir(targetPath);

			// Create symlink (use absolute path for source)
			await symlink(sourcePath, targetPath, "dir");
			log.info(`[worktree] Symlinked: ${dir}`);
		} catch (error) {
			log.warn(`[worktree] Failed to symlink ${dir}: ${error}`);
		}
	}
}

/**
 * Resolve a path that may contain a leading `~` to the user's home directory.
 */
function resolveHomePath(p: string): string {
	if (p === "~" || p.startsWith("~/") || p.startsWith("~\\")) {
		return path.join(os.homedir(), p.slice(1));
	}
	return p;
}

/**
 * Load optional worktree-specific configuration from .opencode/worktree.jsonc.
 * Missing configuration is read-only and falls back to defaults.
 */
async function loadWorktreeConfig(
	directory: string,
	log: Logger,
): Promise<WorktreeConfig> {
	const configPath = path.join(directory, ".opencode", "worktree.jsonc");

	try {
		const file = Bun.file(configPath);
		if (!(await file.exists())) {
			log.debug(
				`[worktree] No optional config at ${configPath}; using defaults`,
			);
			return worktreeConfigSchema.parse({});
		}

		const content = await file.text();
		const parseErrors: ParseError[] = [];
		const parsed = parseJsonc(content, parseErrors, {
			allowTrailingComma: true,
		});
		if (parsed === undefined || parseErrors.length > 0) {
			throw new WorktreeError(
				`Invalid .opencode/worktree.jsonc (${parseErrors.length || 1} syntax error).`,
				"configuration",
			);
		}
		const config = worktreeConfigSchema.parse(parsed);
		if (config.worktreePath) {
			config.worktreePath = resolveHomePath(config.worktreePath);
			if (!path.isAbsolute(config.worktreePath)) {
				throw new WorktreeError(
					"worktreePath must be absolute or start with '~/'",
					"configuration",
				);
			}
		}
		return config;
	} catch (error) {
		if (error instanceof WorktreeError) throw error;
		const message = error instanceof Error ? error.message : String(error);
		throw new WorktreeError(
			`Failed to load .opencode/worktree.jsonc: ${message}`,
			"configuration",
		);
	}
}

type ManagedSessionLookup = (sessionID: string) => object | null;

/**
 * Prevent a worktree session from creating another worktree after its fork.
 * Keep the lookup injectable so the boundary can be tested without opening SQLite.
 */
function isManagedWorktreeSession(
	sessionID: string | undefined,
	lookup: ManagedSessionLookup,
): boolean {
	if (!sessionID) return false;
	return lookup(sessionID) !== null;
}

interface WorkspaceBindingOptions {
	database: Database;
	sessionId: string;
	branch: string;
	baseBranch?: string;
	createWorkspace: (
		branch: string,
		baseBranch?: string,
	) => Promise<{ workspace: WorkspaceInfo; created: boolean }>;
	warpSession: (workspaceId: string, sessionId: string) => Promise<void>;
	removeWorkspace: (workspaceId: string) => Promise<void>;
	claimSessionFn?: typeof claimSession;
	removeSessionFn?: typeof removeSessionById;
	log: Logger;
}

interface WorkspaceBinding {
	workspaceId: string;
	path: string;
}

function errorMessage(error: unknown): string {
	if (error instanceof Error) return error.message;
	if (error && typeof error === "object") {
		const record = error as { message?: unknown; data?: { message?: unknown } };
		if (typeof record.data?.message === "string") return record.data.message;
		if (typeof record.message === "string") return record.message;
	}
	return String(error);
}

function getInProcessFetch(client: unknown): typeof fetch | undefined {
	if (!client || typeof client !== "object") return undefined;
	const embedded = (
		client as { _client?: { getConfig?: () => { fetch?: unknown } } }
	)._client;
	const configuredFetch = embedded?.getConfig?.().fetch;
	return typeof configuredFetch === "function"
		? (configuredFetch as typeof fetch)
		: undefined;
}

function toWorkspaceInfo(workspace: {
	id: string;
	type: string;
	name: string;
	branch?: string | null;
	directory?: string | null;
	extra?: unknown | null;
	projectID: string;
}): WorkspaceInfo {
	return {
		id: workspace.id,
		type: workspace.type,
		name: workspace.name,
		branch: workspace.branch ?? null,
		directory: workspace.directory ?? null,
		extra: workspace.extra ?? null,
		projectID: workspace.projectID,
	};
}

async function bindSessionToWorkspace(
	options: WorkspaceBindingOptions,
): Promise<Result<WorkspaceBinding, string>> {
	const claimSessionFn = options.claimSessionFn ?? claimSession;
	const removeSessionFn = options.removeSessionFn ?? removeSessionById;
	let workspace: WorkspaceInfo | null = null;
	let workspaceCreated = false;
	let sessionClaimed = false;
	const cleanupErrors: string[] = [];

	const cleanup = async (): Promise<void> => {
		if (sessionClaimed) {
			try {
				removeSessionFn(options.database, options.sessionId);
			} catch (error) {
				const detail = `session claim: ${errorMessage(error)}`;
				cleanupErrors.push(detail);
				options.log.warn(`[worktree] Cleanup failed for ${detail}`);
			}
		}
		if (workspace && workspaceCreated) {
			try {
				await options.removeWorkspace(workspace.id);
			} catch (error) {
				const detail = `workspace ${workspace.id}: ${errorMessage(error)}`;
				cleanupErrors.push(detail);
				options.log.warn(`[worktree] Cleanup failed for ${detail}`);
			}
		}
	};

	try {
		const existingLease = getSessionByBranch(options.database, options.branch);
		if (existingLease && existingLease.id !== options.sessionId) {
			throw new Error(
				`Branch "${options.branch}" is already leased by session ${existingLease.id} at ${existingLease.path}`,
			);
		}

		const workspaceResult = await options.createWorkspace(
			options.branch,
			options.baseBranch,
		);
		workspace = workspaceResult.workspace;
		workspaceCreated = workspaceResult.created;
		if (!workspace.id || !workspace.directory) {
			throw new Error(
				"OpenCode returned a workspace without an id or local directory",
			);
		}

		claimSessionFn(options.database, {
			id: options.sessionId,
			branch: options.branch,
			path: workspace.directory,
			workspaceId: workspace.id,
			createdAt: new Date().toISOString(),
		});
		sessionClaimed = true;
		setPendingContinuation(options.database, {
			sessionId: options.sessionId,
			workspaceId: workspace.id,
		});

		await options.warpSession(workspace.id, options.sessionId);
		return Result.ok({ workspaceId: workspace.id, path: workspace.directory });
	} catch (error) {
		await cleanup();
		const cleanupDetail =
			cleanupErrors.length > 0
				? ` Cleanup errors: ${cleanupErrors.join("; ")}.`
				: "";
		return Result.err(`${errorMessage(error)}.${cleanupDetail}`.trim());
	}
}

function parseWorkspaceBaseBranch(extra: unknown): string | undefined {
	if (!extra || typeof extra !== "object") return undefined;
	const baseBranch = (extra as { baseBranch?: unknown }).baseBranch;
	return typeof baseBranch === "string" && baseBranch.length > 0
		? baseBranch
		: undefined;
}

async function resumePendingContinuation(
	database: Database,
	sessionId: string,
	resume: (sessionId: string, workspaceId: string) => Promise<void>,
	log: Logger,
): Promise<boolean> {
	const claimToken = randomUUID();
	const pending = claimPendingContinuation(
		database,
		sessionId,
		claimToken,
		new Date(Date.now() - CONTINUATION_CLAIM_TIMEOUT_MS).toISOString(),
	);
	if (!pending) return false;
	try {
		await resume(sessionId, pending.workspaceId);
		if (!completePendingContinuation(database, sessionId, claimToken)) {
			log.warn(
				`[worktree] Continuation claim changed before completion for session ${sessionId}`,
			);
		}
	} catch (error) {
		releasePendingContinuation(database, sessionId, claimToken);
		log.warn(
			`[worktree] Failed to resume session in workspace: ${errorMessage(error)}`,
		);
	}
	return true;
}

async function resumeAllPendingContinuations(
	database: Database,
	resume: (sessionId: string, workspaceId: string) => Promise<void>,
	log: Logger,
): Promise<void> {
	for (const pending of getAllPendingContinuations(database)) {
		await resumePendingContinuation(database, pending.sessionId, resume, log);
	}
}

function scheduleStartupRecovery(
	recover: () => Promise<void>,
	log: Logger,
): ReturnType<typeof setTimeout> {
	const timer = setTimeout(() => {
		recover().catch((error) => {
			log.warn(
				`[worktree] Startup lifecycle recovery failed: ${errorMessage(error)}`,
			);
		});
	}, 0);
	timer.unref?.();
	return timer;
}

interface RetryableStartupRecovery {
	ensure: () => Promise<boolean>;
	isReady: () => boolean;
}

function createRetryableStartupRecovery(
	recover: () => Promise<void>,
	log: Logger,
): RetryableStartupRecovery {
	let ready = false;
	let activeRecovery: Promise<boolean> | null = null;

	return {
		ensure() {
			if (ready) return Promise.resolve(true);
			if (activeRecovery) return activeRecovery;

			activeRecovery = recover()
				.then(() => {
					ready = true;
					return true;
				})
				.catch((error) => {
					log.warn(
						`[worktree] Workspace lifecycle recovery failed and remains retryable: ${errorMessage(error)}`,
					);
					return false;
				})
				.finally(() => {
					activeRecovery = null;
				});
			return activeRecovery;
		},
		isReady: () => ready,
	};
}

interface ReconciliationResult {
	removedSessionIds: string[];
	orphanedWorkspaceIds: string[];
}

async function reconcileWorkspaceState(
	database: Database,
	workspaces: WorkspaceInfo[],
	log: Logger,
): Promise<ReconciliationResult> {
	const removedSessionIds: string[] = [];
	const claimedWorkspaceIds = new Set<string>();
	const workspaceById = new Map(
		workspaces.map((workspace) => [workspace.id, workspace]),
	);

	for (const session of getAllSessions(database)) {
		let staleReason: string | null = null;
		if (!(await directoryExists(session.path))) {
			staleReason = `directory is missing: ${session.path}`;
		} else if (session.workspaceId) {
			const workspace = workspaceById.get(session.workspaceId);
			if (!workspace) {
				staleReason = `native workspace ${session.workspaceId} is missing`;
			} else if (
				workspace.type !== WORKSPACE_ADAPTER_TYPE ||
				workspace.branch !== session.branch ||
				!workspace.directory ||
				path.resolve(workspace.directory) !== path.resolve(session.path)
			) {
				staleReason = `native workspace ${session.workspaceId} no longer matches its lease`;
			} else {
				claimedWorkspaceIds.add(session.workspaceId);
			}
		}

		if (!staleReason) continue;
		log.warn(
			`[worktree] Removing stale lease for session ${session.id}: ${staleReason}`,
		);
		clearPendingContinuation(database, session.id);
		clearPendingDelete(database, session.id);
		removeSessionById(database, session.id);
		removedSessionIds.push(session.id);
	}

	const orphanedWorkspaceIds = workspaces
		.filter(
			(workspace) =>
				workspace.type === WORKSPACE_ADAPTER_TYPE &&
				!claimedWorkspaceIds.has(workspace.id),
		)
		.map((workspace) => workspace.id);
	for (const workspaceId of orphanedWorkspaceIds) {
		log.warn(
			`[worktree] Native OCX workspace ${workspaceId} has no session lease; it remains read-only until explicitly adopted or removed.`,
		);
	}

	return { removedSessionIds, orphanedWorkspaceIds };
}

type PendingDeleteResult = "none" | "completed" | "cancelled" | "retry";

interface PendingDeleteOptions {
	database: Database;
	sessionId: string;
	mainRoot: string;
	warpSession: (workspaceId: string | null, sessionId: string) => Promise<void>;
	removeNativeWorkspace: (workspaceId: string) => Promise<void>;
	log: Logger;
}

async function processPendingDelete(
	options: PendingDeleteOptions,
): Promise<PendingDeleteResult> {
	const pendingDelete = getPendingDelete(options.database, options.sessionId);
	if (!pendingDelete) return "none";

	const session = getSession(options.database, pendingDelete.sessionId);
	if (!session) {
		options.log.warn(
			"[worktree] Cleanup cancelled: managed session record is missing",
		);
		clearPendingDelete(options.database, pendingDelete.sessionId);
		return "cancelled";
	}

	if (
		pendingDelete.branch !== session.branch ||
		path.resolve(pendingDelete.path) !== path.resolve(session.path)
	) {
		options.log.warn(
			"[worktree] Cleanup cancelled: pending deletion no longer matches its lease",
		);
		clearPendingDelete(options.database, pendingDelete.sessionId);
		return "cancelled";
	}

	const statusResult = await git(["status", "--porcelain"], session.path);
	if (!statusResult.ok) {
		options.log.warn(`[worktree] Cleanup deferred: ${statusResult.error}`);
		return "retry";
	}
	if (statusResult.value) {
		options.log.warn(
			"[worktree] Cleanup cancelled: uncommitted changes remain",
		);
		clearPendingDelete(options.database, pendingDelete.sessionId);
		return "cancelled";
	}

	let detached = false;
	try {
		if (session.workspaceId) {
			await options.warpSession(null, session.id);
			detached = true;
			await options.removeNativeWorkspace(session.workspaceId);
		} else {
			const removeResult = await removeWorktree(options.mainRoot, session.path);
			if (!removeResult.ok) throw new Error(removeResult.error);
		}
		removeSessionById(options.database, session.id);
		return "completed";
	} catch (error) {
		options.log.warn(
			`[worktree] Failed to remove workspace; cleanup remains pending: ${errorMessage(error)}`,
		);
		if (detached && session.workspaceId) {
			try {
				await options.warpSession(session.workspaceId, session.id);
			} catch (restoreError) {
				options.log.warn(
					`[worktree] Failed to restore workspace after cleanup error: ${errorMessage(restoreError)}`,
				);
			}
		}
		return "retry";
	}
}

function createWorkspaceAdapter(
	mainRoot: string,
	log: Logger,
): WorkspaceAdapter {
	return {
		name: "OCX Git worktree",
		description:
			"Isolated git worktree owned by the current orchestrator session",
		async configure(config) {
			if (!config.branch)
				throw new Error("A branch is required for an OCX worktree workspace");
			const branch = parseBranchName(config.branch, "Invalid workspace branch");
			const rawBaseBranch = parseWorkspaceBaseBranch(config.extra);
			if (rawBaseBranch)
				parseBranchName(rawBaseBranch, "Invalid workspace base branch");
			const worktreeConfig = await loadWorktreeConfig(mainRoot, log);
			const existingResult = await existingWorktreeForBranch(mainRoot, branch);
			if (!existingResult.ok) throw new Error(existingResult.error);
			const directory =
				existingResult.value?.path ??
				(await getWorktreePath(mainRoot, branch, worktreeConfig.worktreePath));
			return { ...config, branch, name: branch, directory };
		},
		async create(config) {
			if (!config.branch || !config.directory) {
				throw new Error(
					"Workspace configuration is missing its branch or directory",
				);
			}
			const branch = parseBranchName(config.branch, "Invalid workspace branch");
			const rawBaseBranch = parseWorkspaceBaseBranch(config.extra);
			const baseBranch = rawBaseBranch
				? parseBranchName(rawBaseBranch, "Invalid workspace base branch")
				: undefined;
			const worktreeConfig = await loadWorktreeConfig(mainRoot, log);
			const result = await createWorktree(
				mainRoot,
				branch,
				baseBranch,
				worktreeConfig.worktreePath,
			);
			if (!result.ok) throw new Error(result.error);
			if (path.resolve(result.value.path) !== path.resolve(config.directory)) {
				throw new Error(
					`Workspace path mismatch: ${result.value.path} != ${config.directory}`,
				);
			}
			if (result.value.reused) {
				log.info(
					`[worktree] Reusing existing worktree for ${branch}: ${config.directory}`,
				);
				return;
			}

			if (worktreeConfig.sync.copyFiles.length > 0) {
				await copyFiles(
					mainRoot,
					config.directory,
					worktreeConfig.sync.copyFiles,
					log,
				);
			}
			if (worktreeConfig.sync.symlinkDirs.length > 0) {
				await symlinkDirs(
					mainRoot,
					config.directory,
					worktreeConfig.sync.symlinkDirs,
					log,
				);
			}
		},
		async remove(config) {
			if (!config.directory)
				throw new Error("Workspace configuration is missing its directory");
			const statusResult = await git(
				["status", "--porcelain"],
				config.directory,
			);
			if (!statusResult.ok) throw new Error(statusResult.error);
			if (statusResult.value)
				throw new Error(
					"Refusing to remove a worktree with uncommitted changes",
				);

			const removeResult = await removeWorktree(mainRoot, config.directory);
			if (!removeResult.ok) throw new Error(removeResult.error);
		},
		target(config) {
			if (!config.directory)
				throw new Error("Workspace configuration is missing its directory");
			return { type: "local", directory: config.directory };
		},
	};
}

// =============================================================================
// PLUGIN ENTRY
// =============================================================================

const WorktreePlugin: Plugin = async (ctx) => {
	const { directory, client, experimental_workspace, serverUrl } = ctx;
	const mainRoot = ctx.worktree || directory;

	const log = {
		debug: (msg: string) =>
			client.app
				.log({ body: { service: "worktree", level: "debug", message: msg } })
				.catch(() => {}),
		info: (msg: string) =>
			client.app
				.log({ body: { service: "worktree", level: "info", message: msg } })
				.catch(() => {}),
		warn: (msg: string) =>
			client.app
				.log({ body: { service: "worktree", level: "warn", message: msg } })
				.catch(() => {}),
		error: (msg: string) =>
			client.app
				.log({ body: { service: "worktree", level: "error", message: msg } })
				.catch(() => {}),
	};

	experimental_workspace.register(
		WORKSPACE_ADAPTER_TYPE,
		createWorkspaceAdapter(mainRoot, log),
	);
	const inProcessFetch = getInProcessFetch(client);
	if (!inProcessFetch) {
		log.warn(
			"[worktree] OpenCode in-process transport is unavailable; workspace API may require a listening server",
		);
	}
	const nativeClient = createOpencodeClientV2({
		baseUrl: serverUrl.toString(),
		directory: mainRoot,
		...(inProcessFetch ? { fetch: inProcessFetch } : {}),
	});
	const createNativeWorkspace = async (
		branch: string,
		baseBranch?: string,
	): Promise<{ workspace: WorkspaceInfo; created: boolean }> => {
		const listResponse = await nativeClient.experimental.workspace.list({
			directory: mainRoot,
		});
		if (listResponse.error) throw listResponse.error;
		const existing = listResponse.data?.find(
			(workspace) =>
				workspace.type === WORKSPACE_ADAPTER_TYPE &&
				workspace.branch === branch &&
				!!workspace.directory,
		);
		if (existing?.directory && (await directoryExists(existing.directory))) {
			log.info(
				`[worktree] Reusing registered workspace ${existing.id} for ${branch}`,
			);
			return { workspace: toWorkspaceInfo(existing), created: false };
		}

		const response = await nativeClient.experimental.workspace.create({
			directory: mainRoot,
			type: WORKSPACE_ADAPTER_TYPE,
			branch,
			extra: baseBranch ? { baseBranch } : null,
		});
		if (response.error) throw response.error;
		if (!response.data)
			throw new Error("OpenCode did not return the created workspace");
		return { workspace: toWorkspaceInfo(response.data), created: true };
	};
	const warpSession = async (
		workspaceId: string | null,
		sessionId: string,
	): Promise<void> => {
		const response = await nativeClient.experimental.workspace.warp({
			directory: mainRoot,
			id: workspaceId,
			sessionID: sessionId,
			copyChanges: false,
		});
		if (response.error) throw response.error;
	};
	const removeNativeWorkspace = async (workspaceId: string): Promise<void> => {
		const response = await nativeClient.experimental.workspace.remove({
			directory: mainRoot,
			id: workspaceId,
		});
		if (response.error) throw response.error;
	};
	const continueSessionInWorkspace = async (
		sessionId: string,
		workspaceId: string,
	): Promise<void> => {
		const response = await nativeClient.session.promptAsync({
			directory: mainRoot,
			workspace: workspaceId,
			sessionID: sessionId,
			agent: "build",
			parts: [
				{
					type: "text",
					text: [
						`[ocx-workspace-continuation:${sessionId}:${workspaceId}]`,
						"The approved implementation workspace is now active for this same build session.",
						"Continue the existing task now. Delegate implementation and verification to child agents from this workspace and keep tracking them in this session.",
					].join(" "),
				},
			],
		});
		if (response.error) throw response.error;
	};

	// Shared by the main checkout and all worktrees belonging to the repository.
	const database = await initDb(mainRoot, log);
	const startupRecovery = createRetryableStartupRecovery(async () => {
		const initialWorkspaceList = await nativeClient.experimental.workspace.list(
			{ directory: mainRoot },
		);
		if (initialWorkspaceList.error) {
			throw new Error(
				`Native workspace listing failed: ${errorMessage(initialWorkspaceList.error)}`,
			);
		}
		await reconcileWorkspaceState(
			database,
			(initialWorkspaceList.data ?? []).map((workspace) =>
				toWorkspaceInfo(workspace),
			),
			log,
		);
		for (const pendingDelete of getAllPendingDeletes(database)) {
			await processPendingDelete({
				database,
				sessionId: pendingDelete.sessionId,
				mainRoot,
				warpSession,
				removeNativeWorkspace,
				log,
			});
		}
		await resumeAllPendingContinuations(
			database,
			continueSessionInWorkspace,
			log,
		);
	}, log);
	scheduleStartupRecovery(async () => {
		await startupRecovery.ensure();
	}, log);

	return {
		tool: {
			worktree_create: tool({
				description:
					"Create or safely reuse an isolated git worktree workspace and continue in it with the current session. Ambiguous stale or mismatched paths are reported without mutation.",
				args: {
					branch: tool.schema
						.string()
						.describe(
							"Branch name for the worktree (e.g., 'feature/dark-mode')",
						),
					baseBranch: tool.schema
						.string()
						.optional()
						.describe("Base branch to create from (defaults to HEAD)"),
				},
				async execute(args, toolCtx) {
					if (!(await startupRecovery.ensure())) {
						return "❌ Workspace lifecycle recovery is not ready. Retry after OpenCode finishes startup.";
					}
					if (
						isManagedWorktreeSession(toolCtx?.sessionID, (sessionID) =>
							getSession(database, sessionID),
						)
					) {
						return "❌ worktree_create cannot run from a session already managed by the worktree plugin. Continue in the existing worktree session instead.";
					}

					// Validate branch name at boundary
					const branchResult = branchNameSchema.safeParse(args.branch);
					if (!branchResult.success) {
						return `❌ Invalid branch name: ${branchResult.error.issues[0]?.message}`;
					}

					// Validate base branch name at boundary
					if (args.baseBranch) {
						const baseResult = branchNameSchema.safeParse(args.baseBranch);
						if (!baseResult.success) {
							return `❌ Invalid base branch name: ${baseResult.error.issues[0]?.message}`;
						}
					}

					const binding = await bindSessionToWorkspace({
						database,
						sessionId: toolCtx.sessionID,
						branch: args.branch,
						baseBranch: args.baseBranch,
						createWorkspace: createNativeWorkspace,
						warpSession: async (workspaceId, sessionId) =>
							warpSession(workspaceId, sessionId),
						removeWorkspace: removeNativeWorkspace,
						log,
					});
					if (!binding.ok) {
						return `❌ Failed to create and bind worktree workspace: ${binding.error}`;
					}
					return [
						`Worktree workspace created at ${binding.value.path}.`,
						`The current session (${toolCtx.sessionID}) now owns this workspace.`,
						"End this tool turn without calling more tools. When it becomes idle, the plugin will automatically resume this same session inside the workspace.",
					].join("\n");
				},
			}),

			worktree_delete: tool({
				description:
					"Delete the current worktree and clean up. The working tree must already be clean.",
				args: {
					reason: tool.schema
						.string()
						.describe("Brief explanation of why you are calling this tool"),
				},
				async execute(_args, toolCtx) {
					if (!(await startupRecovery.ensure())) {
						return "❌ Workspace lifecycle recovery is not ready. Retry after OpenCode finishes startup.";
					}
					// Find current session's worktree
					const session = getSession(database, toolCtx?.sessionID ?? "");
					if (!session) {
						return `No worktree associated with this session`;
					}

					const statusResult = await git(
						["status", "--porcelain"],
						session.path,
					);
					if (!statusResult.ok) {
						return `Failed to inspect worktree before cleanup: ${statusResult.error}`;
					}
					if (statusResult.value) {
						return [
							"Cannot delete a worktree with uncommitted changes.",
							"Commit intentionally or discard them explicitly before cleanup.",
						].join(" ");
					}

					// Defer until this exact session is idle; another session must not trigger cleanup.
					setPendingDelete(database, {
						branch: session.branch,
						path: session.path,
						sessionId: session.id,
					});

					return `Worktree marked for cleanup. It will be removed when this session ends.`;
				},
			}),
		},

		event: async ({ event }: { event: Event }): Promise<void> => {
			if (event.type !== "session.idle") return;
			if (!(await startupRecovery.ensure())) return;
			const resumed = await resumePendingContinuation(
				database,
				event.properties.sessionID,
				continueSessionInWorkspace,
				log,
			);
			if (resumed) return;

			await processPendingDelete({
				database,
				sessionId: event.properties.sessionID,
				mainRoot,
				warpSession,
				removeNativeWorkspace,
				log,
			});
		},
	};
};

const WorktreePluginWithInternals = Object.assign(WorktreePlugin, {
	testInternals: {
		bindSessionToWorkspace,
		createWorktree,
		createWorkspaceAdapter,
		createRetryableStartupRecovery,
		getInProcessFetch,
		parseLinkedWorktrees,
		processPendingDelete,
		reconcileWorkspaceState,
		resumeAllPendingContinuations,
		resumePendingContinuation,
		scheduleStartupRecovery,
		copyFiles,
		symlinkDirs,
	},
} as const);

export default WorktreePluginWithInternals;
