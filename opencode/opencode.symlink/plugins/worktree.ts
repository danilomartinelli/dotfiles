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

import type { Database } from "bun:sqlite"
import { constants as fsConstants } from "node:fs"
import { access, copyFile, cp, lstat, mkdir, realpath, rm, stat, symlink } from "node:fs/promises"
import * as os from "node:os"
import * as path from "node:path"
import { type Plugin, tool, type WorkspaceAdapter, type WorkspaceInfo } from "@opencode-ai/plugin"
import type { Event } from "@opencode-ai/sdk"
import { createOpencodeClient as createOpencodeClientV2 } from "@opencode-ai/sdk/v2"
import type { OpencodeClient } from "./kdco-primitives/types"

/** Logger interface for structured logging */
interface Logger {
	debug: (msg: string) => void
	info: (msg: string) => void
	warn: (msg: string) => void
	error: (msg: string) => void
}

import { parse as parseJsonc } from "jsonc-parser"
import { z } from "zod"

import { getProjectId } from "./kdco-primitives/get-project-id"
import {
	type ActiveLaunchContext,
	buildSessionLaunchArgv,
	parseActiveLaunchContext,
	serializePersistedLaunchMetadata,
	toPersistedLaunchMetadata,
} from "./worktree/launch-context"
import {
	clearPendingDelete,
	claimSession,
	getPendingDelete,
	getSession,
	getWorktreePath,
	initStateDb,
	removeSessionById,
	setPendingDelete,
} from "./worktree/state"
import { openTerminal, type TerminalResult } from "./worktree/terminal"

/** Maximum retries for database initialization */
const DB_MAX_RETRIES = 3

/** Delay between retry attempts in milliseconds */
const DB_RETRY_DELAY_MS = 100

/** Maximum depth to traverse session parent chain */
const MAX_SESSION_CHAIN_DEPTH = 10

const WORKSPACE_ADAPTER_TYPE = "ocx-git-worktree"

// =============================================================================
// TYPES & SCHEMAS
// =============================================================================

/** Result type for fallible operations */
interface OkResult<T> {
	readonly ok: true
	readonly value: T
}
interface ErrResult<E> {
	readonly ok: false
	readonly error: E
}
type Result<T, E> = OkResult<T> | ErrResult<E>

const Result = {
	ok: <T>(value: T): OkResult<T> => ({ ok: true, value }),
	err: <E>(error: E): ErrResult<E> => ({ ok: false, error }),
}

/**
 * Git branch name validation - blocks invalid refs and shell metacharacters
 * Characters blocked: control chars (0x00-0x1f, 0x7f), ~^:?*[]\\, and shell metacharacters
 */
function isValidBranchName(name: string): boolean {
	// Check for control characters
	for (let i = 0; i < name.length; i++) {
		const code = name.charCodeAt(i)
		if (code <= 0x1f || code === 0x7f) return false
	}
	// Check for invalid git ref characters and shell metacharacters
	if (/[~^:?*[\]\\;&|`$()]/.test(name)) return false
	return true
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
	.refine((name) => isValidBranchName(name), "Contains invalid git ref characters")
	.refine((name) => !name.startsWith(".") && !name.endsWith("."), "Cannot start or end with dot")
	.refine((name) => !name.endsWith(".lock"), "Cannot end with .lock")

/**
 * Worktree plugin configuration schema.
 * Config file: .opencode/worktree.jsonc
 */
const worktreeConfigSchema = z.object({
	/** Custom base path for worktree storage. Supports ~ for home directory. */
	worktreePath: z.string().optional(),
	sync: z
		.object({
			/** Files to copy from main worktree (relative paths only) */
			copyFiles: z.array(z.string()).default([]),
			/** Directories to symlink from main worktree (saves disk space) */
			symlinkDirs: z.array(z.string()).default([]),
			/** Patterns to exclude from copying (reserved for future use) */
			exclude: z.array(z.string()).default([]),
		})
		.default(() => ({ copyFiles: [], symlinkDirs: [], exclude: [] })),
	hooks: z
		.object({
			/** Commands to run after worktree creation */
			postCreate: z.array(z.string()).default([]),
			/** Commands to run before worktree deletion */
			preDelete: z.array(z.string()).default([]),
		})
		.default(() => ({ postCreate: [], preDelete: [] })),
})

type WorktreeConfig = z.infer<typeof worktreeConfigSchema>

// =============================================================================
// ERROR TYPES
// =============================================================================

class WorktreeError extends Error {
	constructor(
		message: string,
		public readonly operation: string,
		public readonly cause?: unknown,
	) {
		super(`${operation}: ${message}`)
		this.name = "WorktreeError"
	}
}

type ResolveExecutable = (command: string) => string | null | undefined
type ValidateProfileAvailability = (
	ocxBin: string,
	profile: string,
) => Promise<Result<void, string>>

interface LaunchExecutableValidationOptions {
	resolveExecutable?: ResolveExecutable
	pathExists?: (absolutePath: string) => Promise<boolean>
}

function isPathLikeCommand(command: string): boolean {
	return command.includes("/") || command.includes("\\")
}

function resolveStableLaunchBinaryPath(
	ocxBin: string,
	baseDirectory: string,
	resolveExecutable: ResolveExecutable,
): Result<string, string> {
	if (isPathLikeCommand(ocxBin)) {
		const resolvedPath = path.isAbsolute(ocxBin) ? ocxBin : path.resolve(baseDirectory, ocxBin)
		return Result.ok(resolvedPath)
	}

	const resolvedFromPath = resolveExecutable(ocxBin)
	if (!resolvedFromPath) {
		return Result.err(`Configured OCX binary "${ocxBin}" is not available in PATH.`)
	}

	const resolvedPath = path.isAbsolute(resolvedFromPath)
		? resolvedFromPath
		: path.resolve(baseDirectory, resolvedFromPath)

	return Result.ok(resolvedPath)
}

async function pathPointsToLaunchableBinary(absolutePath: string): Promise<boolean> {
	try {
		const stats = await stat(absolutePath)
		if (stats.isDirectory()) {
			return false
		}

		await access(absolutePath, fsConstants.X_OK)
		return true
	} catch {
		return false
	}
}

async function ensureLaunchContextExecutable(
	launchContext: ActiveLaunchContext,
	baseDirectory: string,
	options: LaunchExecutableValidationOptions = {},
): Promise<ActiveLaunchContext> {
	if (launchContext.mode === "plain") {
		return launchContext
	}

	const { ocxBin, profile } = launchContext
	const resolveExecutable = options.resolveExecutable ?? ((command: string) => Bun.which(command))
	const pathExists = options.pathExists ?? pathPointsToLaunchableBinary
	const resolvedPathResult = resolveStableLaunchBinaryPath(ocxBin, baseDirectory, resolveExecutable)
	if (!resolvedPathResult.ok) {
		throw new WorktreeError(
			`${resolvedPathResult.error} Repair the parent OCX profile (${profile}) and recreate this worktree session.`,
			"launch",
		)
	}

	const resolvedPath = resolvedPathResult.value
	const isLaunchable = await pathExists(resolvedPath)
	if (!isLaunchable) {
		throw new WorktreeError(
			`Configured OCX binary "${ocxBin}" resolved to "${resolvedPath}" but is missing or stale. Repair the parent OCX profile (${profile}) and recreate this worktree session.`,
			"launch",
		)
	}

	return {
		mode: "ocx",
		ocxBin: resolvedPath,
		profile,
	}
}

async function validateOcxProfileAvailability(
	ocxBin: string,
	profile: string,
): Promise<Result<void, string>> {
	try {
		const proc = Bun.spawn([ocxBin, "profile", "show", profile, "--global", "--json"], {
			stdout: "pipe",
			stderr: "pipe",
		})
		const [exitCode, stdout, stderr] = await Promise.all([
			proc.exited,
			new Response(proc.stdout).text(),
			new Response(proc.stderr).text(),
		])

		if (exitCode === 0) {
			return Result.ok(undefined)
		}

		const detail = stderr.trim() || stdout.trim() || `exit ${exitCode}`
		return Result.err(detail)
	} catch (error) {
		return Result.err(error instanceof Error ? error.message : String(error))
	}
}

async function ensureLaunchContextProfile(
	launchContext: ActiveLaunchContext,
	validateProfileAvailability: ValidateProfileAvailability = validateOcxProfileAvailability,
): Promise<void> {
	if (launchContext.mode === "plain") {
		return
	}

	const validationResult = await validateProfileAvailability(
		launchContext.ocxBin,
		launchContext.profile,
	)
	if (validationResult.ok) {
		return
	}

	throw new WorktreeError(
		`Configured OCX profile "${launchContext.profile}" is missing or stale. ${validationResult.error} Repair the parent OCX profile and recreate this worktree session.`,
		"launch",
	)
}

// =============================================================================
// SESSION FORKING HELPERS
// =============================================================================

/**
 * Check if a path exists, distinguishing ENOENT from other errors (Law 4)
 */
async function pathExists(filePath: string): Promise<boolean> {
	try {
		await access(filePath)
		return true
	} catch (e: unknown) {
		if (e && typeof e === "object" && "code" in e && e.code === "ENOENT") {
			return false
		}
		throw e // Re-throw permission errors, etc.
	}
}

/**
 * Copy file if source exists. Returns true if copied, false if source doesn't exist.
 * Throws on copy failure (Law 4: Fail Loud)
 */
async function copyIfExists(src: string, dest: string): Promise<boolean> {
	if (!(await pathExists(src))) return false
	await copyFile(src, dest)
	return true
}

/**
 * Copy directory contents if source exists.
 * @param src - Source directory path
 * @param dest - Destination directory path
 * @returns true if copy was performed, false if source doesn't exist
 */
async function copyDirIfExists(src: string, dest: string): Promise<boolean> {
	if (!(await pathExists(src))) return false
	await cp(src, dest, { recursive: true })
	return true
}

interface ForkResult {
	forkedSession: { id: string }
	rootSessionId: string
	planCopied: boolean
	delegationsCopied: boolean
}

interface FinalizeWorktreeLaunchOptions {
	database: Database
	worktreePath: string
	launchArgv: string[]
	branch: string
	forkedSessionId: string
	sessionRecord: {
		id: string
		branch: string
		path: string
		createdAt: string
		launchMode: "plain" | "ocx"
		profile: string | null
		ocxBin: string | null
	}
	log: Logger
	openTerminalFn?: (cwd: string, argv?: string[], windowName?: string) => Promise<TerminalResult>
	claimSessionFn?: typeof claimSession
	removeSessionFn?: typeof removeSessionById
	deleteForkedSessionFn?: (sessionId: string) => Promise<void>
	removeWorktreeFn?: () => Promise<void>
}

async function finalizeWorktreeLaunch(
	options: FinalizeWorktreeLaunchOptions,
): Promise<TerminalResult> {
	const openTerminalFn = options.openTerminalFn ?? openTerminal
	const claimSessionFn = options.claimSessionFn ?? claimSession
	const removeSessionFn = options.removeSessionFn ?? removeSessionById
	const deleteForkedSessionFn = options.deleteForkedSessionFn
	const cleanupErrors: string[] = []
	let sessionClaimed = false

	const recordCleanupError = (operation: string, error: unknown): void => {
		const message = error instanceof Error ? error.message : String(error)
		cleanupErrors.push(`${operation}: ${message}`)
		options.log.warn(`[worktree] ${operation} failed: ${message}`)
	}

	const cleanupLaunchArtifacts = async (): Promise<void> => {
		if (sessionClaimed) {
			try {
				removeSessionFn(options.database, options.forkedSessionId)
			} catch (error) {
				recordCleanupError(
					`Failed to remove claimed session ${options.forkedSessionId}`,
					error,
				)
			}
		}

		if (deleteForkedSessionFn) {
			try {
				await deleteForkedSessionFn(options.forkedSessionId)
			} catch (error) {
				recordCleanupError(
					`Failed to delete forked session ${options.forkedSessionId}`,
					error,
				)
			}
		}

		if (options.removeWorktreeFn) {
			try {
				await options.removeWorktreeFn()
			} catch (error) {
				recordCleanupError("Failed to remove worktree after launch failure", error)
			}
		}
	}

	try {
		// Claim durably before starting the child terminal. The child can only
		// inherit the nested-worktree guard after this write succeeds.
		claimSessionFn(options.database, options.sessionRecord)
		sessionClaimed = true
	} catch (error) {
		await cleanupLaunchArtifacts()
		const message = error instanceof Error ? error.message : String(error)
		const cleanupDetail = cleanupErrors.length > 0 ? ` Cleanup failed: ${cleanupErrors.join("; ")}` : ""
		return {
			success: false,
			error: `Failed to register forked session before terminal launch: ${message}.${cleanupDetail}`,
		}
	}

	let terminalResult: TerminalResult
	try {
		terminalResult = await openTerminalFn(
			options.worktreePath,
			options.launchArgv,
			options.branch,
		)
	} catch (error) {
		terminalResult = {
			success: false,
			error: error instanceof Error ? error.message : String(error),
		}
	}

	if (terminalResult.success) return terminalResult

	await cleanupLaunchArtifacts()
	const cleanupDetail = cleanupErrors.length > 0 ? ` Cleanup failed: ${cleanupErrors.join("; ")}` : ""
	return {
		...terminalResult,
		error: `${terminalResult.error ?? "Terminal launch failed"}.${cleanupDetail}`,
	}
}

/**
 * Fork a session and copy associated plans/delegations.
 * Cleans up forked session on failure (atomic operation).
 */
async function forkWithContext(
	client: OpencodeClient,
	sessionId: string,
	projectId: string,
	getRootSessionIdFn: (sessionId: string) => Promise<string>,
): Promise<ForkResult> {
	// Guard clauses (Law 1)
	if (!client) throw new WorktreeError("client is required", "forkWithContext")
	if (!sessionId) throw new WorktreeError("sessionId is required", "forkWithContext")
	if (!projectId) throw new WorktreeError("projectId is required", "forkWithContext")

	// Get root session ID with error wrapping
	let rootSessionId: string
	try {
		rootSessionId = await getRootSessionIdFn(sessionId)
	} catch (e) {
		throw new WorktreeError("Failed to get root session ID", "forkWithContext", e)
	}

	// Fork session
	const forkedSessionResponse = await client.session.fork({
		path: { id: sessionId },
		body: {},
	})
	const forkedSession = forkedSessionResponse.data
	if (!forkedSession?.id) {
		throw new WorktreeError("Failed to fork session: no session data returned", "forkWithContext")
	}

	// Copy data with cleanup on failure
	let planCopied = false
	let delegationsCopied = false

	try {
		const workspaceBase = path.join(os.homedir(), ".local", "share", "opencode", "workspace")
		const delegationsBase = path.join(os.homedir(), ".local", "share", "opencode", "delegations")

		const destWorkspaceDir = path.join(workspaceBase, projectId, forkedSession.id)
		const destDelegationsDir = path.join(delegationsBase, projectId, forkedSession.id)

		await mkdir(destWorkspaceDir, { recursive: true })
		await mkdir(destDelegationsDir, { recursive: true })

		// Copy plan
		const srcPlan = path.join(workspaceBase, projectId, rootSessionId, "plan.md")
		const destPlan = path.join(destWorkspaceDir, "plan.md")
		planCopied = await copyIfExists(srcPlan, destPlan)

		// Copy delegations
		const srcDelegations = path.join(delegationsBase, projectId, rootSessionId)
		delegationsCopied = await copyDirIfExists(srcDelegations, destDelegationsDir)
	} catch (error) {
		client.app
			.log({
				body: {
					service: "worktree",
					level: "error",
					message: `forkWithContext: Copy failed, cleaning up forked session: ${error}`,
				},
			})
			.catch(() => {})
		// Clean up orphaned directories
		const workspaceBase = path.join(os.homedir(), ".local", "share", "opencode", "workspace")
		const delegationsBase = path.join(os.homedir(), ".local", "share", "opencode", "delegations")
		const destWorkspaceDir = path.join(workspaceBase, projectId, forkedSession.id)
		const destDelegationsDir = path.join(delegationsBase, projectId, forkedSession.id)
		await rm(destWorkspaceDir, { recursive: true, force: true }).catch((e) => {
			client.app
				.log({
					body: {
						service: "worktree",
						level: "error",
						message: `forkWithContext: Failed to clean up workspace dir ${destWorkspaceDir}: ${e}`,
					},
				})
				.catch(() => {})
		})
		await rm(destDelegationsDir, { recursive: true, force: true }).catch((e) => {
			client.app
				.log({
					body: {
						service: "worktree",
						level: "error",
						message: `forkWithContext: Failed to clean up delegations dir ${destDelegationsDir}: ${e}`,
					},
				})
				.catch(() => {})
		})
		await client.session.delete({ path: { id: forkedSession.id } }).catch((e) => {
			client.app
				.log({
					body: {
						service: "worktree",
						level: "error",
						message: `forkWithContext: Failed to clean up forked session ${forkedSession.id}: ${e}`,
					},
				})
				.catch(() => {})
		})
		throw new WorktreeError(
			`Failed to copy session data: ${error instanceof Error ? error.message : String(error)}`,
			"forkWithContext",
			error,
		)
	}

	return { forkedSession, rootSessionId, planCopied, delegationsCopied }
}

// =============================================================================
// MODULE-LEVEL STATE
// =============================================================================

/** Database instance - initialized once per plugin lifecycle */
let db: Database | null = null

/** Project root path - stored on first initialization */
let projectRoot: string | null = null

/** Flag to prevent duplicate cleanup handler registration */
let cleanupRegistered = false

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
	if (cleanupRegistered) return // Early exit guard
	cleanupRegistered = true

	const cleanup = () => {
		try {
			database.exec("PRAGMA wal_checkpoint(TRUNCATE)")
			database.close()
		} catch {
			// Best effort cleanup - process is exiting anyway
		}
	}

	process.once("SIGTERM", cleanup)
	process.once("SIGINT", cleanup)
	process.once("beforeExit", cleanup)
}

/**
 * Get the database instance, initializing if needed.
 * Includes retry logic for transient initialization failures.
 *
 * @returns Database instance
 * @throws {Error} if initialization fails after all retries
 */
async function getDb(log: Logger): Promise<Database> {
	if (db) return db

	if (!projectRoot) {
		throw new Error("Database not initialized: projectRoot not set. Call initDb() first.")
	}

	let lastError: Error | null = null

	for (let attempt = 1; attempt <= DB_MAX_RETRIES; attempt++) {
		try {
			db = await initStateDb(projectRoot)
			registerCleanupHandlers(db)
			return db
		} catch (error) {
			lastError = error instanceof Error ? error : new Error(String(error))
			log.warn(`Database init attempt ${attempt}/${DB_MAX_RETRIES} failed: ${lastError.message}`)

			if (attempt < DB_MAX_RETRIES) {
				Bun.sleepSync(DB_RETRY_DELAY_MS)
			}
		}
	}

	throw new Error(
		`Failed to initialize database after ${DB_MAX_RETRIES} attempts: ${lastError?.message}`,
	)
}

/**
 * Initialize the database with the project root path.
 * Must be called once before any getDb() calls.
 */
async function initDb(root: string, log: Logger): Promise<Database> {
	projectRoot = root
	return getDb(log)
}

// =============================================================================
// GIT MODULE
// =============================================================================

/**
 * Execute a git command safely using Bun.spawn with explicit array.
 * Avoids shell interpolation entirely by passing args as array.
 */
async function git(args: string[], cwd: string): Promise<Result<string, string>> {
	try {
		const proc = Bun.spawn(["git", ...args], {
			cwd,
			stdout: "pipe",
			stderr: "pipe",
		})
		const [stdout, stderr, exitCode] = await Promise.all([
			new Response(proc.stdout).text(),
			new Response(proc.stderr).text(),
			proc.exited,
		])
		if (exitCode !== 0) {
			return Result.err(stderr.trim() || `git ${args[0]} failed`)
		}
		return Result.ok(stdout.trim())
	} catch (error) {
		return Result.err(error instanceof Error ? error.message : String(error))
	}
}

async function branchExists(cwd: string, branch: string): Promise<boolean> {
	const result = await git(["rev-parse", "--verify", branch], cwd)
	return result.ok
}

interface LinkedWorktree {
	path: string
	branch: string | null
	prunable: boolean
}

function parseLinkedWorktrees(output: string): LinkedWorktree[] {
	return output
		.split("\0\0")
		.map((entry) => entry.split("\0").filter(Boolean))
		.filter((fields) => fields.length > 0)
		.map((fields) => {
			const worktreeField = fields.find((field) => field.startsWith("worktree "))
			const branchField = fields.find((field) => field.startsWith("branch refs/heads/"))
			return {
				path: worktreeField?.slice("worktree ".length) ?? "",
				branch: branchField?.slice("branch refs/heads/".length) ?? null,
				prunable: fields.some((field) => field === "prunable" || field.startsWith("prunable ")),
			}
		})
		.filter((worktree) => worktree.path.length > 0)
}

async function listLinkedWorktrees(repoRoot: string): Promise<Result<LinkedWorktree[], string>> {
	const result = await git(["worktree", "list", "--porcelain", "-z"], repoRoot)
	return result.ok ? Result.ok(parseLinkedWorktrees(result.value)) : result
}

async function existingWorktreeForBranch(
	repoRoot: string,
	branch: string,
): Promise<Result<LinkedWorktree | null, string>> {
	const result = await listLinkedWorktrees(repoRoot)
	if (!result.ok) return result
	return Result.ok(result.value.find((worktree) => worktree.branch === branch) ?? null)
}

async function directoryExists(directory: string): Promise<boolean> {
	const info = await stat(directory).catch(() => null)
	return info?.isDirectory() ?? false
}

async function createWorktree(
	repoRoot: string,
	branch: string,
	baseBranch?: string,
	basePath?: string,
): Promise<Result<{ path: string; reused: boolean }, string>> {
	const worktreePath = await getWorktreePath(repoRoot, branch, basePath)
	const existingResult = await existingWorktreeForBranch(repoRoot, branch)
	if (!existingResult.ok) return existingResult
	const existing = existingResult.value
	if (existing) {
		if (existing.prunable || !(await directoryExists(existing.path))) {
			return Result.err(
				`The branch "${branch}" has a stale worktree registration at ${existing.path}. ` +
					"Choose whether to prune/archive that registration or use a different branch; no cleanup was performed automatically.",
			)
		}
		return Result.ok({ path: existing.path, reused: true })
	}

	if (await pathExists(worktreePath)) {
		return Result.err(
			`The target path ${worktreePath} already exists but is not the registered worktree for branch "${branch}". ` +
				"Choose whether to archive/remove it or create a workspace with a different branch; nothing was overwritten.",
		)
	}

	// Ensure parent directory exists
	await mkdir(path.dirname(worktreePath), { recursive: true })

	const exists = await branchExists(repoRoot, branch)

	if (exists) {
		// Checkout existing branch into worktree
		const result = await git(["worktree", "add", worktreePath, branch], repoRoot)
		return result.ok ? Result.ok({ path: worktreePath, reused: false }) : result
	} else {
		// Create new branch from base
		const base = baseBranch ?? "HEAD"
		const result = await git(["worktree", "add", "-b", branch, worktreePath, base], repoRoot)
		return result.ok ? Result.ok({ path: worktreePath, reused: false }) : result
	}
}

async function removeWorktree(
	repoRoot: string,
	worktreePath: string,
): Promise<Result<void, string>> {
	const result = await git(["worktree", "remove", "--force", worktreePath], repoRoot)
	return result.ok ? Result.ok(undefined) : Result.err(result.error)
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
		log.warn(`[worktree] Rejected absolute path: ${filePath}`)
		return false
	}
	// Reject obvious path traversal
	if (filePath.includes("..")) {
		log.warn(`[worktree] Rejected path traversal: ${filePath}`)
		return false
	}
	// Verify resolved path stays within base directory
	const resolved = path.resolve(baseDir, filePath)
	if (!resolved.startsWith(baseDir + path.sep) && resolved !== baseDir) {
		log.warn(`[worktree] Path escapes base directory: ${filePath}`)
		return false
	}
	return true
}

function isWithinRealRoot(rootRealPath: string, candidateRealPath: string): boolean {
	const relative = path.relative(rootRealPath, candidateRealPath)
	return relative === "" || (!!relative && !relative.startsWith("..") && !path.isAbsolute(relative))
}

async function resolveExistingPathWithinRoot(
	rootDir: string,
	relativePath: string,
	log: Logger,
): Promise<string | null> {
	const rootRealPath = await realpath(rootDir).catch(() => null)
	if (!rootRealPath) {
		log.warn(`[worktree] Failed to resolve worktree root: ${rootDir}`)
		return null
	}

	const candidatePath = path.resolve(rootDir, relativePath)
	const candidateRealPath = await realpath(candidatePath).catch(() => null)
	if (!candidateRealPath) return null

	if (!isWithinRealRoot(rootRealPath, candidateRealPath)) {
		log.warn(`[worktree] Rejected path escaping worktree via symlink: ${relativePath}`)
		return null
	}

	return candidateRealPath
}

async function ensureDirectoryWithinRoot(
	rootDir: string,
	relativeDir: string,
	log: Logger,
): Promise<string | null> {
	const rootRealPath = await realpath(rootDir).catch(() => null)
	if (!rootRealPath) {
		log.warn(`[worktree] Failed to resolve worktree root: ${rootDir}`)
		return null
	}

	const rootPath = path.resolve(rootDir)
	const targetDir = path.resolve(rootDir, relativeDir)
	const resolvedRootRelative = path.relative(rootPath, targetDir)
	if (
		resolvedRootRelative !== "" &&
		(resolvedRootRelative.startsWith("..") || path.isAbsolute(resolvedRootRelative))
	) {
		log.warn(`[worktree] Rejected path escaping worktree: ${relativeDir}`)
		return null
	}

	const rootRelative = path.relative(rootDir, targetDir)
	const parts = rootRelative.split(path.sep).filter(Boolean)
	let cursor = rootDir

	for (const part of parts) {
		cursor = path.join(cursor, part)
		const entry = await lstat(cursor).catch(() => null)
		if (entry?.isSymbolicLink()) {
			log.warn(`[worktree] Rejected symlinked target parent: ${relativeDir}`)
			return null
		}
		if (entry && !entry.isDirectory()) {
			log.warn(`[worktree] Rejected non-directory target parent: ${relativeDir}`)
			return null
		}
		if (!entry) {
			await mkdir(cursor)
		}
	}

	const finalRealPath = await realpath(targetDir).catch(() => null)
	if (!finalRealPath || !isWithinRealRoot(rootRealPath, finalRealPath)) {
		log.warn(`[worktree] Rejected path escaping worktree via symlink: ${relativeDir}`)
		return null
	}

	return targetDir
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
		if (!isPathSafe(file, sourceDir, log)) continue

		const sourcePath = await resolveExistingPathWithinRoot(sourceDir, file, log)
		if (!sourcePath) continue

		const targetPath = path.join(targetDir, file)

		try {
			const sourceFile = Bun.file(sourcePath)
			if (!(await sourceFile.exists())) {
				log.debug(`[worktree] Skipping missing file: ${file}`)
				continue
			}

			// Ensure target directory exists
			const targetFileDir = path.dirname(targetPath)
			const targetFileRelativeDir = path.relative(targetDir, targetFileDir)
			if (!(await ensureDirectoryWithinRoot(targetDir, targetFileRelativeDir, log))) continue

			const existingTarget = await lstat(targetPath).catch(() => null)
			if (existingTarget?.isSymbolicLink()) {
				log.warn(`[worktree] Rejected symlinked target file: ${file}`)
				continue
			}

			// Copy file
			await Bun.write(targetPath, sourceFile)
			log.info(`[worktree] Copied: ${file}`)
		} catch (error) {
			const isNotFound =
				error instanceof Error &&
				(error.message.includes("ENOENT") || error.message.includes("no such file"))
			if (isNotFound) {
				log.debug(`[worktree] Skipping missing: ${file}`)
			} else {
				log.warn(`[worktree] Failed to copy ${file}: ${error}`)
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
		if (!isPathSafe(dir, sourceDir, log)) continue

		const sourcePath = await resolveExistingPathWithinRoot(sourceDir, dir, log)
		if (!sourcePath) continue

		const targetPath = path.join(targetDir, dir)

		try {
			// Check if source directory exists
			const fileStat = await stat(sourcePath).catch(() => null)
			if (!fileStat?.isDirectory()) {
				log.debug(`[worktree] Skipping missing directory: ${dir}`)
				continue
			}

			// Ensure parent directory exists
			const targetParentDir = path.dirname(targetPath)
			const targetParentRelativeDir = path.relative(targetDir, targetParentDir)
			if (!(await ensureDirectoryWithinRoot(targetDir, targetParentRelativeDir, log))) continue

			const existingTarget = await lstat(targetPath).catch(() => null)
			if (existingTarget?.isSymbolicLink()) {
				log.warn(`[worktree] Rejected symlinked target: ${dir}`)
				continue
			}

			// Remove existing target if it exists (might be empty dir from git)
			await rm(targetPath, { recursive: true, force: true })

			// Create symlink (use absolute path for source)
			await symlink(sourcePath, targetPath, "dir")
			log.info(`[worktree] Symlinked: ${dir}`)
		} catch (error) {
			log.warn(`[worktree] Failed to symlink ${dir}: ${error}`)
		}
	}
}

/**
 * Run hook commands in the worktree directory.
 */
async function runHooks(cwd: string, commands: string[], log: Logger): Promise<void> {
	for (const command of commands) {
		log.info(`[worktree] Running hook: ${command}`)
		try {
			// Use shell to properly handle quoted arguments and complex commands
			const result = Bun.spawnSync(["bash", "-c", command], {
				cwd,
				stdout: "inherit",
				stderr: "pipe",
			})
			if (result.exitCode !== 0) {
				const stderr = result.stderr?.toString() || ""
				log.warn(
					`[worktree] Hook failed (exit ${result.exitCode}): ${command}${stderr ? `\n${stderr}` : ""}`,
				)
			}
		} catch (error) {
			log.warn(`[worktree] Hook error: ${error}`)
		}
	}
}

/**
 * Resolve a path that may contain a leading `~` to the user's home directory.
 */
function resolveHomePath(p: string): string {
	if (p === "~" || p.startsWith("~/") || p.startsWith("~\\")) {
		return path.join(os.homedir(), p.slice(1))
	}
	return p
}

/**
 * Load optional worktree-specific configuration from .opencode/worktree.jsonc.
 * Missing configuration is read-only and falls back to defaults.
 */
async function loadWorktreeConfig(directory: string, log: Logger): Promise<WorktreeConfig> {
	const configPath = path.join(directory, ".opencode", "worktree.jsonc")

	try {
		const file = Bun.file(configPath)
		if (!(await file.exists())) {
			log.debug(`[worktree] No optional config at ${configPath}; using defaults`)
			return worktreeConfigSchema.parse({})
		}

		const content = await file.text()
		// Use proper JSONC parser (handles comments in strings correctly)
		const parsed = parseJsonc(content)
		if (parsed === undefined) {
			log.error(`[worktree] Invalid worktree.jsonc syntax`)
			return worktreeConfigSchema.parse({})
		}
		const config = worktreeConfigSchema.parse(parsed)
		if (config.worktreePath) {
			config.worktreePath = resolveHomePath(config.worktreePath)
		}
		return config
	} catch (error) {
		log.warn(`[worktree] Failed to load config: ${error}`)
		return worktreeConfigSchema.parse({})
	}
}

type ManagedSessionLookup = (sessionID: string) => object | null

/**
 * Prevent a worktree session from creating another worktree after its fork.
 * Keep the lookup injectable so the boundary can be tested without opening SQLite.
 */
function isManagedWorktreeSession(
	sessionID: string | undefined,
	lookup: ManagedSessionLookup,
): boolean {
	if (!sessionID) return false
	return lookup(sessionID) !== null
}

interface WorkspaceBindingOptions {
	database: Database
	sessionId: string
	branch: string
	baseBranch?: string
	createWorkspace: (branch: string, baseBranch?: string) => Promise<WorkspaceInfo>
	warpSession: (workspaceId: string, sessionId: string) => Promise<void>
	removeWorkspace: (workspaceId: string) => Promise<void>
	claimSessionFn?: typeof claimSession
	removeSessionFn?: typeof removeSessionById
	log: Logger
}

interface WorkspaceBinding {
	workspaceId: string
	path: string
}

function errorMessage(error: unknown): string {
	if (error instanceof Error) return error.message
	if (error && typeof error === "object") {
		const record = error as { message?: unknown; data?: { message?: unknown } }
		if (typeof record.data?.message === "string") return record.data.message
		if (typeof record.message === "string") return record.message
	}
	return String(error)
}

function getInProcessFetch(client: unknown): typeof fetch | undefined {
	if (!client || typeof client !== "object") return undefined
	const embedded = (client as { _client?: { getConfig?: () => { fetch?: unknown } } })._client
	const configuredFetch = embedded?.getConfig?.().fetch
	return typeof configuredFetch === "function" ? (configuredFetch as typeof fetch) : undefined
}

function toWorkspaceInfo(workspace: {
	id: string
	type: string
	name: string
	branch?: string | null
	directory?: string | null
	extra?: unknown | null
	projectID: string
}): WorkspaceInfo {
	return {
		id: workspace.id,
		type: workspace.type,
		name: workspace.name,
		branch: workspace.branch ?? null,
		directory: workspace.directory ?? null,
		extra: workspace.extra ?? null,
		projectID: workspace.projectID,
	}
}

async function bindSessionToWorkspace(
	options: WorkspaceBindingOptions,
): Promise<Result<WorkspaceBinding, string>> {
	const claimSessionFn = options.claimSessionFn ?? claimSession
	const removeSessionFn = options.removeSessionFn ?? removeSessionById
	let workspace: WorkspaceInfo | null = null
	let sessionClaimed = false
	const cleanupErrors: string[] = []

	const cleanup = async (): Promise<void> => {
		if (sessionClaimed) {
			try {
				removeSessionFn(options.database, options.sessionId)
			} catch (error) {
				const detail = `session claim: ${errorMessage(error)}`
				cleanupErrors.push(detail)
				options.log.warn(`[worktree] Cleanup failed for ${detail}`)
			}
		}
		if (workspace) {
			try {
				await options.removeWorkspace(workspace.id)
			} catch (error) {
				const detail = `workspace ${workspace.id}: ${errorMessage(error)}`
				cleanupErrors.push(detail)
				options.log.warn(`[worktree] Cleanup failed for ${detail}`)
			}
		}
	}

	try {
		workspace = await options.createWorkspace(options.branch, options.baseBranch)
		if (!workspace.id || !workspace.directory) {
			throw new Error("OpenCode returned a workspace without an id or local directory")
		}

		claimSessionFn(options.database, {
			id: options.sessionId,
			branch: options.branch,
			path: workspace.directory,
			workspaceId: workspace.id,
			createdAt: new Date().toISOString(),
		})
		sessionClaimed = true

		await options.warpSession(workspace.id, options.sessionId)
		return Result.ok({ workspaceId: workspace.id, path: workspace.directory })
	} catch (error) {
		await cleanup()
		const cleanupDetail = cleanupErrors.length > 0 ? ` Cleanup errors: ${cleanupErrors.join("; ")}.` : ""
		return Result.err(`${errorMessage(error)}.${cleanupDetail}`.trim())
	}
}

function parseWorkspaceBaseBranch(extra: unknown): string | undefined {
	if (!extra || typeof extra !== "object") return undefined
	const baseBranch = (extra as { baseBranch?: unknown }).baseBranch
	return typeof baseBranch === "string" && baseBranch.length > 0 ? baseBranch : undefined
}

async function resumePendingContinuation(
	pending: Map<string, string>,
	sessionId: string,
	resume: (sessionId: string, workspaceId: string) => Promise<void>,
	log: Logger,
): Promise<boolean> {
	const workspaceId = pending.get(sessionId)
	if (!workspaceId) return false
	pending.delete(sessionId)
	try {
		await resume(sessionId, workspaceId)
	} catch (error) {
		log.warn(`[worktree] Failed to resume session in workspace: ${errorMessage(error)}`)
	}
	return true
}

function createWorkspaceAdapter(mainRoot: string, log: Logger): WorkspaceAdapter {
	return {
		name: "OCX Git worktree",
		description: "Isolated git worktree owned by the current orchestrator session",
		async configure(config) {
			if (!config.branch) throw new Error("A branch is required for an OCX worktree workspace")
			const worktreeConfig = await loadWorktreeConfig(mainRoot, log)
			const existingResult = await existingWorktreeForBranch(mainRoot, config.branch)
			if (!existingResult.ok) throw new Error(existingResult.error)
			const directory =
				existingResult.value?.path ??
				(await getWorktreePath(mainRoot, config.branch, worktreeConfig.worktreePath))
			return { ...config, name: config.branch, directory }
		},
		async create(config) {
			if (!config.branch || !config.directory) {
				throw new Error("Workspace configuration is missing its branch or directory")
			}
			const worktreeConfig = await loadWorktreeConfig(mainRoot, log)
			const result = await createWorktree(
				mainRoot,
				config.branch,
				parseWorkspaceBaseBranch(config.extra),
				worktreeConfig.worktreePath,
			)
			if (!result.ok) throw new Error(result.error)
			if (path.resolve(result.value.path) !== path.resolve(config.directory)) {
				throw new Error(`Workspace path mismatch: ${result.value.path} != ${config.directory}`)
			}
			if (result.value.reused) {
				log.info(`[worktree] Reusing existing worktree for ${config.branch}: ${config.directory}`)
				return
			}

			if (worktreeConfig.sync.copyFiles.length > 0) {
				await copyFiles(mainRoot, config.directory, worktreeConfig.sync.copyFiles, log)
			}
			if (worktreeConfig.sync.symlinkDirs.length > 0) {
				await symlinkDirs(mainRoot, config.directory, worktreeConfig.sync.symlinkDirs, log)
			}
			if (worktreeConfig.hooks.postCreate.length > 0) {
				await runHooks(config.directory, worktreeConfig.hooks.postCreate, log)
			}
		},
		async remove(config) {
			if (!config.directory) throw new Error("Workspace configuration is missing its directory")
			const statusResult = await git(["status", "--porcelain"], config.directory)
			if (!statusResult.ok) throw new Error(statusResult.error)
			if (statusResult.value) throw new Error("Refusing to remove a worktree with uncommitted changes")

			const worktreeConfig = await loadWorktreeConfig(mainRoot, log)
			if (worktreeConfig.hooks.preDelete.length > 0) {
				await runHooks(config.directory, worktreeConfig.hooks.preDelete, log)
			}
			const postHookStatus = await git(["status", "--porcelain"], config.directory)
			if (!postHookStatus.ok) throw new Error(postHookStatus.error)
			if (postHookStatus.value) {
				throw new Error("Pre-delete hooks left uncommitted changes; workspace cleanup cancelled")
			}

			const removeResult = await removeWorktree(mainRoot, config.directory)
			if (!removeResult.ok) throw new Error(removeResult.error)
		},
		target(config) {
			if (!config.directory) throw new Error("Workspace configuration is missing its directory")
			return { type: "local", directory: config.directory }
		},
	}
}

// =============================================================================
// PLUGIN ENTRY
// =============================================================================

const WorktreePlugin: Plugin = async (ctx) => {
	const { directory, client, experimental_workspace, serverUrl } = ctx
	const mainRoot = ctx.worktree || directory

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
	}

	experimental_workspace.register(WORKSPACE_ADAPTER_TYPE, createWorkspaceAdapter(mainRoot, log))
	const inProcessFetch = getInProcessFetch(client)
	if (!inProcessFetch) {
		log.warn("[worktree] OpenCode in-process transport is unavailable; workspace API may require a listening server")
	}
	const nativeClient = createOpencodeClientV2({
		baseUrl: serverUrl.toString(),
		directory: mainRoot,
		...(inProcessFetch ? { fetch: inProcessFetch } : {}),
	})
	const createNativeWorkspace = async (
		branch: string,
		baseBranch?: string,
	): Promise<WorkspaceInfo> => {
		const listResponse = await nativeClient.experimental.workspace.list({ directory: mainRoot })
		if (listResponse.error) throw listResponse.error
		const existing = listResponse.data?.find(
			(workspace) =>
				workspace.type === WORKSPACE_ADAPTER_TYPE &&
				workspace.branch === branch &&
				!!workspace.directory,
		)
		if (existing?.directory && (await directoryExists(existing.directory))) {
			log.info(`[worktree] Reusing registered workspace ${existing.id} for ${branch}`)
			return toWorkspaceInfo(existing)
		}

		const response = await nativeClient.experimental.workspace.create({
			directory: mainRoot,
			type: WORKSPACE_ADAPTER_TYPE,
			branch,
			extra: baseBranch ? { baseBranch } : null,
		})
		if (response.error) throw response.error
		if (!response.data) throw new Error("OpenCode did not return the created workspace")
		return toWorkspaceInfo(response.data)
	}
	const warpSession = async (workspaceId: string | null, sessionId: string): Promise<void> => {
		const response = await nativeClient.experimental.workspace.warp({
			directory: mainRoot,
			id: workspaceId,
			sessionID: sessionId,
			copyChanges: false,
		})
		if (response.error) throw response.error
	}
	const removeNativeWorkspace = async (workspaceId: string): Promise<void> => {
		const response = await nativeClient.experimental.workspace.remove({
			directory: mainRoot,
			id: workspaceId,
		})
		if (response.error) throw response.error
	}
	const pendingContinuations = new Map<string, string>()
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
						"The approved implementation workspace is now active for this same build session.",
						"Continue the existing task now. Delegate implementation and verification to child agents from this workspace and keep tracking them in this session.",
					].join(" "),
				},
			],
		})
		if (response.error) throw response.error
	}

	// Shared by the main checkout and all worktrees belonging to the repository.
	const database = await initDb(mainRoot, log)

	return {
		tool: {
			worktree_create: tool({
				description:
					"Create or safely reuse an isolated git worktree workspace and continue in it with the current session. Ambiguous stale or mismatched paths are reported without mutation.",
				args: {
					branch: tool.schema
						.string()
						.describe("Branch name for the worktree (e.g., 'feature/dark-mode')"),
					baseBranch: tool.schema
						.string()
						.optional()
						.describe("Base branch to create from (defaults to HEAD)"),
				},
				async execute(args, toolCtx) {
					if (isManagedWorktreeSession(toolCtx?.sessionID, (sessionID) =>
						getSession(database, sessionID),
					)) {
						return "❌ worktree_create cannot run from a session already managed by the worktree plugin. Continue in the existing worktree session instead."
					}

					// Validate branch name at boundary
					const branchResult = branchNameSchema.safeParse(args.branch)
					if (!branchResult.success) {
						return `❌ Invalid branch name: ${branchResult.error.issues[0]?.message}`
					}

					// Validate base branch name at boundary
					if (args.baseBranch) {
						const baseResult = branchNameSchema.safeParse(args.baseBranch)
						if (!baseResult.success) {
							return `❌ Invalid base branch name: ${baseResult.error.issues[0]?.message}`
						}
					}

					const binding = await bindSessionToWorkspace({
						database,
						sessionId: toolCtx.sessionID,
						branch: args.branch,
						baseBranch: args.baseBranch,
						createWorkspace: createNativeWorkspace,
						warpSession: async (workspaceId, sessionId) => warpSession(workspaceId, sessionId),
						removeWorkspace: removeNativeWorkspace,
						log,
					})
					if (!binding.ok) {
						return `❌ Failed to create and bind worktree workspace: ${binding.error}`
					}
					pendingContinuations.set(toolCtx.sessionID, binding.value.workspaceId)

					return [
						`Worktree workspace created at ${binding.value.path}.`,
						`The current session (${toolCtx.sessionID}) now owns this workspace.`,
						"End this tool turn without calling more tools. When it becomes idle, the plugin will automatically resume this same session inside the workspace.",
					].join("\n")
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
					// Find current session's worktree
					const session = getSession(database, toolCtx?.sessionID ?? "")
					if (!session) {
						return `No worktree associated with this session`
					}

					const statusResult = await git(["status", "--porcelain"], session.path)
					if (!statusResult.ok) {
						return `Failed to inspect worktree before cleanup: ${statusResult.error}`
					}
					if (statusResult.value) {
						return [
							"Cannot delete a worktree with uncommitted changes.",
							"Commit intentionally or discard them explicitly before cleanup.",
						].join(" ")
					}

					// Defer until this exact session is idle; another session must not trigger cleanup.
					setPendingDelete(
						database,
						{ branch: session.branch, path: session.path, sessionId: session.id },
						client,
					)

					return `Worktree marked for cleanup. It will be removed when this session ends.`
				},
			}),
		},

		event: async ({ event }: { event: Event }): Promise<void> => {
			if (event.type !== "session.idle") return
			const resumed = await resumePendingContinuation(
				pendingContinuations,
				event.properties.sessionID,
				continueSessionInWorkspace,
				log,
			)
			if (resumed) return

			// Handle pending delete
			const pendingDelete = getPendingDelete(database)
			if (!pendingDelete || pendingDelete.sessionId !== event.properties.sessionID) return

			const session = getSession(database, pendingDelete.sessionId)
			if (!session) {
				log.warn(`[worktree] Cleanup cancelled: managed session record is missing`)
				clearPendingDelete(database)
				return
			}

			// Recheck at the idle boundary so changes made after the tool call are
			// never committed or discarded implicitly.
			const statusResult = await git(["status", "--porcelain"], session.path)
			if (!statusResult.ok || statusResult.value) {
				const detail = statusResult.ok ? "uncommitted changes remain" : statusResult.error
				log.warn(`[worktree] Cleanup cancelled: ${detail}`)
				clearPendingDelete(database)
				return
			}

			let detached = false
			try {
				if (session.workspaceId) {
					await warpSession(null, session.id)
					detached = true
					await removeNativeWorkspace(session.workspaceId)
				} else {
					// Backward compatibility for sessions created before native workspaces.
					const config = await loadWorktreeConfig(mainRoot, log)
					if (config.hooks.preDelete.length > 0) {
						await runHooks(session.path, config.hooks.preDelete, log)
					}
					const removeResult = await removeWorktree(mainRoot, session.path)
					if (!removeResult.ok) throw new Error(removeResult.error)
				}
				removeSessionById(database, session.id)
				clearPendingDelete(database)
			} catch (error) {
				log.warn(`[worktree] Failed to remove workspace: ${errorMessage(error)}`)
				if (detached && session.workspaceId) {
					try {
						await warpSession(session.workspaceId, session.id)
					} catch (restoreError) {
						log.warn(
							`[worktree] Failed to restore workspace after cleanup error: ${errorMessage(restoreError)}`,
						)
					}
				}
				clearPendingDelete(database)
			}
		},
	}
}

const WorktreePluginWithInternals = Object.assign(WorktreePlugin, {
	testInternals: {
		bindSessionToWorkspace,
		createWorktree,
		createWorkspaceAdapter,
		getInProcessFetch,
		parseLinkedWorktrees,
		resumePendingContinuation,
		isPathLikeCommand,
		copyFiles,
		ensureLaunchContextExecutable,
		validateOcxProfileAvailability,
		ensureLaunchContextProfile,
		finalizeWorktreeLaunch,
		symlinkDirs,
	},
} as const)

export default WorktreePluginWithInternals
