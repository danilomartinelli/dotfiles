/**
 * background-agents
 * Unified delegation system for OpenCode
 *
 * Replaces native `task` tool with persistent, async-first agent delegation.
 * All agent outputs are persisted to storage, orchestrator receives only key references.
 *
 * Based on oh-my-opencode by @code-yeongyu (MIT License)
 * https://github.com/code-yeongyu/oh-my-opencode
 */

import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import { type Plugin, type ToolContext, tool } from "@opencode-ai/plugin";
import type { Event, Message, Part, TextPart } from "@opencode-ai/sdk";
import {
	adjectives,
	animals,
	colors,
	uniqueNamesGenerator,
} from "unique-names-generator";
import { getProjectId } from "../kdco-primitives/get-project-id";
import { assertSafeStorageSegment } from "../kdco-primitives/storage-id";
import type { OpencodeClient } from "../kdco-primitives/types";
import { getAllSessions, getSession, initStateDb } from "../worktree/state";

// ==========================================
// READABLE ID GENERATION
// ==========================================

function generateReadableId(): string {
	return uniqueNamesGenerator({
		dictionaries: [adjectives, colors, animals],
		separator: "-",
		length: 3,
		style: "lowerCase",
	});
}

// ==========================================
// METADATA GENERATION (using small_model)
// ==========================================

interface GeneratedMetadata {
	title: string;
	description: string;
}

/**
 * Generate title and description from result content using small_model
 * Falls back to truncation if small_model unavailable
 */
async function generateMetadata(
	client: OpencodeClient,
	resultContent: string,
	parentID: string,
	debugLog: (msg: string) => Promise<void>,
): Promise<GeneratedMetadata> {
	const fallbackMetadata = (): GeneratedMetadata => {
		// Fallback: truncate first line/paragraph
		const firstLine =
			resultContent.split("\n").find((l) => l.trim().length > 0) ||
			"Delegation result";
		const title =
			firstLine.slice(0, 30).trim() + (firstLine.length > 30 ? "..." : "");
		const description =
			resultContent.slice(0, 150).trim() +
			(resultContent.length > 150 ? "..." : "");
		return { title, description };
	};

	try {
		// Get config to check for small_model
		const config = await client.config.get();
		const configData = config.data as { small_model?: string } | undefined;

		if (!configData?.small_model) {
			await debugLog(
				"generateMetadata: No small_model configured, using fallback",
			);
			return fallbackMetadata();
		}

		await debugLog(
			`generateMetadata: Using small_model ${configData.small_model}`,
		);

		// Create a session for metadata generation
		const session = await client.session.create({
			body: {
				title: "Metadata Generation",
				parentID,
			},
		});

		if (!session.data?.id) {
			await debugLog("generateMetadata: Failed to create session");
			return fallbackMetadata();
		}

		// Prompt the small model for metadata
		const prompt = `Generate a title and description for this research result.

RULES:
- Title: 2-5 words, max 30 characters, sentence case
- Description: 2-3 sentences, max 150 characters, summarize key findings

RESULT CONTENT:
${resultContent.slice(0, 2000)}

Respond with ONLY valid JSON in this exact format:
{"title": "Your Title Here", "description": "Your description here."}`;

		// Await prompt response directly with timeout safety net
		const PROMPT_TIMEOUT_MS = 30000;
		const result = await Promise.race([
			client.session.prompt({
				path: { id: session.data.id },
				body: {
					parts: [{ type: "text", text: prompt }],
				},
			}),
			new Promise<never>((_, reject) =>
				setTimeout(
					() => reject(new Error("Prompt timeout after 30s")),
					PROMPT_TIMEOUT_MS,
				),
			),
		]);

		// Extract text from the response
		const responseParts = result.data?.parts as TextPart[] | undefined;
		const textPart = responseParts?.find(
			(p): p is TextPart => p.type === "text",
		);
		if (!textPart) {
			await debugLog("generateMetadata: No text part in response");
			return fallbackMetadata();
		}

		// Parse JSON response
		const jsonMatch = textPart.text.match(/\{[\s\S]*\}/);
		if (!jsonMatch) {
			await debugLog(
				`generateMetadata: No JSON found in response: ${textPart.text}`,
			);
			return fallbackMetadata();
		}

		const parsed = JSON.parse(jsonMatch[0]) as {
			title?: string;
			description?: string;
		};
		if (!parsed.title || !parsed.description) {
			await debugLog("generateMetadata: Invalid JSON structure");
			return fallbackMetadata();
		}

		await debugLog(`generateMetadata: Generated title="${parsed.title}"`);
		return {
			title: parsed.title.slice(0, 30),
			description: parsed.description.slice(0, 150),
		};
	} catch (error) {
		await debugLog(
			`generateMetadata error: ${error instanceof Error ? error.message : "Unknown error"}`,
		);
		return fallbackMetadata();
	}
}

// ==========================================
// TYPE DEFINITIONS
// ==========================================

interface SessionMessageItem {
	info: Message;
	parts: Part[];
}

interface AssistantSessionMessageItem {
	info: Message & { role: "assistant" };
	parts: Part[];
}

type DelegationStatus =
	| "registered"
	| "running"
	| "complete"
	| "error"
	| "cancelled"
	| "timeout";

type DelegationTerminalStatus = Extract<
	DelegationStatus,
	"complete" | "error" | "cancelled" | "timeout"
>;

interface DelegationProgress {
	toolCalls: number;
	lastUpdateAt: Date;
	lastHeartbeatAt: Date;
	lastMessage?: string;
	lastMessageAt?: Date;
}

interface DelegationNotificationState {
	terminalNotifiedAt?: Date;
	terminalNotificationCount: number;
}

interface ParentNotificationState {
	allCompleteNotifiedAt?: Date;
	allCompleteNotificationCount: number;
	allCompleteCycle: number;
	allCompleteCycleToken: string;
	allCompleteNotifiedCycle?: number;
	allCompleteNotifiedCycleToken?: string;
	allCompleteScheduledCycle?: number;
	allCompleteScheduledCycleToken?: string;
	allCompleteScheduledTimer?: ReturnType<typeof setTimeout>;
}

interface DelegationRetrievalState {
	retrievedAt?: Date;
	retrievalCount: number;
	lastReaderSessionID?: string;
}

interface DelegationArtifactState {
	filePath: string;
	persistedAt?: Date;
	byteLength?: number;
	persistError?: string;
}

interface DelegationRecord {
	id: string;
	rootSessionID: string;
	sessionID: string;
	parentSessionID: string;
	parentMessageID: string;
	parentAgent: string;
	prompt: string;
	agent: string;
	notificationCycle: number;
	notificationCycleToken: string;
	status: DelegationStatus;
	createdAt: Date;
	startedAt?: Date;
	completedAt?: Date;
	updatedAt: Date;
	timeoutAt: Date;
	progress: DelegationProgress;
	notification: DelegationNotificationState;
	retrieval: DelegationRetrievalState;
	artifact: DelegationArtifactState;
	error?: string;
	title?: string;
	description?: string;
	result?: string;
}

const DEFAULT_MAX_RUN_TIME_MS = 15 * 60 * 1000; // 15 minutes
const TERMINAL_WAIT_GRACE_MS = 10_000;
const READ_POLL_INTERVAL_MS = 250;
const ALL_COMPLETE_QUIET_PERIOD_MS = 50;
const PARENT_NOTIFICATION_TIMEOUT_MS = 5_000;

interface DelegateInput {
	parentSessionID: string;
	parentMessageID: string;
	parentAgent: string;
	prompt: string;
	agent: string;
}

interface DelegationListItem {
	id: string;
	status: DelegationStatus;
	title?: string;
	description?: string;
	agent?: string;
	unread?: boolean;
}

interface DelegationManagerOptions {
	maxRunTimeMs?: number;
	readPollIntervalMs?: number;
	terminalWaitGraceMs?: number;
	allCompleteQuietPeriodMs?: number;
	idGenerator?: () => string;
	metadataGenerator?: typeof generateMetadata;
}

// ==========================================
// LOGGING HELPER
// ==========================================

/**
 * Create a structured logger that sends messages to OpenCode's log API.
 * Catches errors silently to avoid disrupting tool execution.
 */
function createLogger(client: OpencodeClient) {
	const log = (level: "debug" | "info" | "warn" | "error", message: string) =>
		client.app
			.log({ body: { service: "background-agents", level, message } })
			.catch(() => {});
	return {
		debug: (msg: string) => log("debug", msg),
		info: (msg: string) => log("info", msg),
		warn: (msg: string) => log("warn", msg),
		error: (msg: string) => log("error", msg),
	};
}

type Logger = ReturnType<typeof createLogger>;

// ==========================================
// AGENT CAPABILITY DETECTION
// ==========================================

/**
 * Parse agent mode at boundary.
 * Returns trusted type indicating if agent is a sub-agent.
 */
async function parseAgentMode(
	client: OpencodeClient,
	agentName: string,
	log: Logger,
): Promise<{ isSubAgent: boolean }> {
	try {
		const result = await client.app.agents({});
		const agents = (result.data ?? []) as { name: string; mode?: string }[];
		const agent = agents.find((a) => a.name === agentName);
		if (!agent) {
			throw new Error(`Agent "${agentName}" is not installed`);
		}
		return { isSubAgent: agent?.mode === "subagent" };
	} catch (error) {
		// The native task route is a capability boundary. If the installed agent
		// mode cannot be proven, do not allow the call to bypass delegation rules.
		const message = error instanceof Error ? error.message : String(error);
		log.warn(
			`Agent mode lookup failed for "${agentName}"; denying native task: ${message}`,
		);
		throw new Error(
			`Cannot authorize native task for agent "${agentName}": ${message}`,
		);
	}
}

/**
 * Permission entry type: simple value or pattern object.
 * Matches CLI schema: z.union([z.enum(["ask", "allow", "deny"]), z.record(z.enum(...))])
 */
type PermissionEntry =
	| "ask"
	| "allow"
	| "deny"
	| Record<string, "ask" | "allow" | "deny">;

/**
 * Return true only when every possible input is denied.
 *
 * A wildcard deny followed by an allow/ask exception is still a capability.
 * Treating it as fully denied would let a shell command such as `git branch*`
 * cross the read-only delegation boundary.
 */
function isPermissionCompletelyDenied(
	entry: PermissionEntry | undefined,
): boolean {
	if (entry === "deny") return true;
	if (!entry || typeof entry !== "object") return false;
	if (entry["*"] !== "deny") return false;
	return Object.values(entry).every((value) => value === "deny");
}

const MUTATING_TOOLS = [
	"edit",
	"write",
	"apply_patch",
	"bash",
	"oc_edit",
	"oc_write",
	"oc_bash",
	"shell",
	"mkdir",
	"oc_mkdir",
	"rm",
	"oc_rm",
	"plan_save",
	"worktree_create",
	"worktree_delete",
	"task",
	"delegate",
] as const;

const PROVIDER_TOOL_ALIASES = new Set([
	"oc_bash",
	"shell",
	"oc_read",
	"oc_write",
	"oc_edit",
	"ls",
	"oc_ls",
	"oc_glob",
	"mkdir",
	"oc_mkdir",
	"rm",
	"oc_rm",
	"stat",
	"oc_stat",
]);

function permissionKeyMatchesTool(
	permissionKey: string,
	toolName: string,
): boolean {
	const escaped = permissionKey
		.replace(/[.+?^${}()|[\]\\]/g, "\\$&")
		.replaceAll("*", ".*");
	return new RegExp(`^${escaped}$`).test(toolName);
}

function resolveToolPermission(
	globalPermission: Record<string, PermissionEntry>,
	agentPermission: Record<string, PermissionEntry>,
	toolName: string,
): PermissionEntry | undefined {
	let resolved: PermissionEntry | undefined;
	for (const permission of [globalPermission, agentPermission]) {
		for (const [key, entry] of Object.entries(permission)) {
			if (permissionKeyMatchesTool(key, toolName)) resolved = entry;
		}
	}
	return resolved;
}

function isAgentPermissionReadOnly(
	globalPermission: Record<string, PermissionEntry>,
	agentPermission: Record<string, PermissionEntry>,
): boolean {
	return MUTATING_TOOLS.every((toolName) =>
		isPermissionCompletelyDenied(
			resolveToolPermission(globalPermission, agentPermission, toolName),
		),
	);
}

/**
 * Resolve the agent that owns a session from the persisted user message.
 * Agent identity is runtime state, so parse it at the hook boundary instead
 * of trusting tool arguments supplied by the child task.
 */
async function parseSessionAgent(
	client: OpencodeClient,
	sessionID: string,
	log: Logger,
): Promise<string | undefined> {
	try {
		const result = await client.session.messages({ path: { id: sessionID } });
		const messages = (result.data ?? []) as Array<{
			info?: { role?: string; agent?: string };
		}>;

		for (const message of messages.slice().reverse()) {
			if (message.info?.role !== "user") continue;
			const agent = message.info.agent?.trim();
			if (agent) return agent;
		}

		return undefined;
	} catch (error) {
		log.warn(
			`Session agent lookup failed for "${sessionID}": ${error instanceof Error ? error.message : String(error)}`,
		);
		return undefined;
	}
}

function isPlanDelegatingToWriteCapable(
	parentAgent: string | undefined,
	isTargetReadOnly: boolean,
): boolean {
	return parentAgent === "plan" && !isTargetReadOnly;
}

const WRITE_LEAF_AGENTS = new Set(["coder", "scribe"]);
const DELEGATION_ORCHESTRATORS = new Set(["plan", "build"]);
const SCRIBE_EXTENSIONS = new Set([".md", ".mdx", ".txt", ".rst", ".adoc"]);
const CODER_MUTATING_GIT_VERBS = [
	"add",
	"checkout",
	"cherry-pick",
	"clean",
	"commit",
	"config",
	"fetch",
	"merge",
	"notes",
	"pull",
	"push",
	"rebase",
	"reset",
	"restore",
	"revert",
	"switch",
] as const;
const BUILD_MUTATING_GIT_VERBS = [
	"add",
	"commit",
	"fetch",
	"pull",
	"push",
	"rebase",
] as const;

function shellContainsGitVerb(
	command: string,
	verbs: readonly string[],
): boolean {
	return verbs.some((verb) =>
		new RegExp(
			`\\bgit\\b[^;&|\\n]*\\b${verb.replace("-", "\\-")}\\b`,
			"i",
		).test(command),
	);
}

function gitPushSegments(command: string): string[] {
	return command.match(/\bgit\b[^;&|\n]*\bpush\b[^;&|\n]*/gi) ?? [];
}

function isLeaseProtectedForcePushCommand(command: string): boolean {
	return gitPushSegments(command).some((segment) =>
		/(?:^|\s)--force-with-lease(?:=[^\s;&|]+)?(?:\s|$)/i.test(segment),
	);
}

function isUnsafeForcePushCommand(command: string): boolean {
	return gitPushSegments(command).some(
		(segment) =>
			/(?:^|\s)--force(?:\s|$)/i.test(segment) ||
			/(?:^|\s)--mirror(?:\s|$)/i.test(segment) ||
			/(?:^|\s)-[A-Za-z]*f[A-Za-z]*(?:\s|$)/.test(segment),
	);
}

function isForcePushCommand(command: string): boolean {
	return (
		isLeaseProtectedForcePushCommand(command) ||
		isUnsafeForcePushCommand(command)
	);
}

const CODER_READ_ONLY_STATEFUL_GIT_COMMANDS = [
	/^git\s+branch$/i,
	/^git\s+branch\s+--show-current$/i,
	/^git\s+branch\s+--list(?:\s+.*)?$/i,
	/^git\s+branch\s+(?:-a|--all|-r|--remotes|-v|-vv)(?:\s+--no-color)?$/i,
	/^git\s+remote$/i,
	/^git\s+remote\s+-v$/i,
	/^git\s+remote\s+get-url(?:\s+.*)?$/i,
	/^git\s+remote\s+show(?:\s+.*)?$/i,
	/^git\s+stash\s+(?:list|show)(?:\s+.*)?$/i,
	/^git\s+tag$/i,
	/^git\s+tag\s+--list(?:\s+.*)?$/i,
	/^git\s+worktree\s+list(?:\s+.*)?$/i,
] as const;

function coderStatefulGitInspectionViolation(command: string): string | null {
	const gitSegments = command.match(/\bgit\b[^;&|\n]*/gi) ?? [];
	for (const segment of gitSegments) {
		const normalized = segment.trim().replace(/\s+/g, " ");
		if (
			/(?:^|\s)(?:-C(?:\s|$)|--git-dir(?:=|\s)|--work-tree(?:=|\s))/i.test(
				normalized,
			)
		) {
			return "Git path overrides may escape the managed worktree";
		}

		const tokens = normalized.split(" ");
		let subcommandIndex = 1;
		while (
			["--no-pager", "--paginate", "-p", "--literal-pathspecs", "--no-optional-locks"].includes(
				tokens[subcommandIndex] ?? "",
			)
		) {
			subcommandIndex += 1;
		}
		const subcommand = tokens[subcommandIndex] ?? "";
		if (subcommand.startsWith("-")) {
			if (
				tokens
					.slice(subcommandIndex + 1)
					.some((token) => /^(?:branch|remote|stash|tag|worktree)$/i.test(token))
			) {
				return "unsupported Git global options precede a repository-state command";
			}
			continue;
		}
		if (!/^(?:branch|remote|stash|tag|worktree)$/i.test(subcommand)) {
			continue;
		}
		const canonicalCommand = `git ${tokens.slice(subcommandIndex).join(" ")}`;
		if (
			/^git\s+(?:branch\s+--list|tag\s+--list)\b/i.test(canonicalCommand) &&
			/(?:^|\s)(?:-d|-D|-m|-M|-c|-C|--delete|--move|--copy|--edit-description|--set-upstream-to|--unset-upstream)(?:\s|=|$)/.test(
				canonicalCommand,
			)
		) {
			return "Git repository-state mutations belong to the build orchestrator";
		}
		if (
			CODER_READ_ONLY_STATEFUL_GIT_COMMANDS.some((pattern) =>
				pattern.test(canonicalCommand),
			)
		) {
			continue;
		}
		return "Git repository-state mutations belong to the build orchestrator";
	}
	return null;
}

function coderShellPolicyViolation(command: string): string | null {
	if (isForcePushCommand(command)) return "force-push is forbidden";
	if (shellContainsGitVerb(command, CODER_MUTATING_GIT_VERBS)) {
		return "Git delivery and repository-state mutations belong to the build orchestrator";
	}
	const statefulGitViolation = coderStatefulGitInspectionViolation(command);
	if (statefulGitViolation) return statefulGitViolation;
	if (
		/\b(?:gh\s+pr\s+create|glab\s+mr\s+create|npm\s+publish|bun\s+publish|sudo)\b/i.test(
			command,
		)
	) {
		return "publishing, pull-request creation, and privileged commands are forbidden for coder";
	}
	return null;
}

function isBuildShellMutation(command: string): boolean {
	return (
		shellContainsGitVerb(command, BUILD_MUTATING_GIT_VERBS) ||
		/\b(?:gh\s+pr\s+create|glab\s+mr\s+create)\b/i.test(command)
	);
}

async function isLinkedWorktree(
	directory: string,
	log: Logger,
): Promise<boolean> {
	try {
		const gitProcess = Bun.spawn(
			["git", "rev-parse", "--git-dir", "--git-common-dir"],
			{
				cwd: directory,
				stdout: "pipe",
				stderr: "pipe",
			},
		);
		const [stdout, stderr, exitCode] = await Promise.all([
			new Response(gitProcess.stdout).text(),
			new Response(gitProcess.stderr).text(),
			gitProcess.exited,
		]);
		if (exitCode !== 0) {
			log.warn(
				`Unable to resolve Git worktree identity for "${directory}": ${stderr.trim() || "git rev-parse failed"}`,
			);
			return false;
		}

		const [gitDirectory, commonGitDirectory] = stdout.trim().split(/\r?\n/);
		if (!gitDirectory || !commonGitDirectory) {
			log.warn(`Unable to resolve Git worktree identity for "${directory}"`);
			return false;
		}

		const resolveGitPath = (gitPath: string): string =>
			path.resolve(
				path.isAbsolute(gitPath) ? gitPath : path.join(directory, gitPath),
			);
		return resolveGitPath(gitDirectory) !== resolveGitPath(commonGitDirectory);
	} catch (error) {
		log.warn(
			`Unable to resolve Git worktree identity for "${directory}": ${error instanceof Error ? error.message : String(error)}`,
		);
		return false;
	}
}

function isPathWithinRoot(root: string, candidate: string): boolean {
	const relative = path.relative(root, candidate);
	return (
		relative === "" ||
		(!!relative && !relative.startsWith("..") && !path.isAbsolute(relative))
	);
}

async function mutationTargetViolation(
	directory: string,
	targetPath: string,
): Promise<string | null> {
	if (!targetPath.trim()) return "the target path is empty";

	const lexicalRoot = path.resolve(directory);
	const lexicalTarget = path.resolve(directory, targetPath);
	if (!isPathWithinRoot(lexicalRoot, lexicalTarget)) {
		return `target path escapes the managed worktree: ${targetPath}`;
	}

	const realRoot = await fs.realpath(lexicalRoot).catch(() => null);
	if (!realRoot) return `managed worktree cannot be resolved: ${directory}`;

	let existingAncestor = lexicalTarget;
	while (true) {
		const entry = await fs.lstat(existingAncestor).catch((error: unknown) => {
			if (
				error instanceof Error &&
				"code" in error &&
				(error as NodeJS.ErrnoException).code === "ENOENT"
			)
				return null;
			throw error;
		});
		if (entry) break;
		const parent = path.dirname(existingAncestor);
		if (parent === existingAncestor) {
			return `target path has no resolvable ancestor: ${targetPath}`;
		}
		existingAncestor = parent;
	}

	const realAncestor = await fs.realpath(existingAncestor).catch(() => null);
	if (!realAncestor || !isPathWithinRoot(realRoot, realAncestor)) {
		return `target path escapes the managed worktree through a symlink: ${targetPath}`;
	}
	return null;
}

async function trustedTemporaryHandoffRoot(
	targetPath: string,
): Promise<string | null> {
	if (!path.isAbsolute(targetPath) || !/handoff/i.test(path.basename(targetPath)))
		return null;

	for (const root of new Set([os.tmpdir(), "/tmp", "/private/tmp"])) {
		if (!(await mutationTargetViolation(root, targetPath))) return root;
	}
	return null;
}

interface MutationToolArgs {
	filePath?: string;
	path?: string;
	patch?: string;
	patchText?: string;
	patch_text?: string;
	input?: string;
}

function extractApplyPatchPaths(args: MutationToolArgs | undefined): string[] {
	const patchText = [
		args?.patch,
		args?.patchText,
		args?.patch_text,
		args?.input,
	].find((value): value is string => typeof value === "string");
	if (!patchText) return [];

	const paths = [
		...patchText.matchAll(/^\*\*\* (?:Add|Update|Delete) File:\s*(.+?)\s*$/gm),
		...patchText.matchAll(/^\*\*\* Move to:\s*(.+?)\s*$/gm),
	].map((match) => match[1]);
	return [...new Set(paths)];
}

/**
 * Parse agent write capability at boundary.
 * Returns trusted type indicating if agent is read-only.
 *
 * An agent is read-only only when every direct and indirect mutation route is
 * completely denied after global and agent-specific rules are composed.
 */
async function parseAgentWriteCapability(
	client: OpencodeClient,
	agentName: string,
	log: Logger,
): Promise<{ isReadOnly: boolean }> {
	try {
		const config = await client.config.get();
		const configData = config.data as {
			permission?: Record<string, PermissionEntry>;
			agent?: Record<
				string,
				{
					permission?: Record<string, PermissionEntry>;
				}
			>;
		};
		const globalPermission = configData?.permission ?? {};
		const agentPermission = configData?.agent?.[agentName]?.permission ?? {};

		return {
			isReadOnly: isAgentPermissionReadOnly(globalPermission, agentPermission),
		};
	} catch (error) {
		// Fail-safe: Config errors shouldn't block task calls
		// Fail-loud: Log for observability
		log.warn(
			`Config fetch failed for "${agentName}", assuming write-capable: ${error instanceof Error ? error.message : String(error)}`,
		);
		return { isReadOnly: false };
	}
}

/**
 * DELEGATION MANAGER
 */
function isTerminalStatus(
	status: DelegationStatus,
): status is DelegationTerminalStatus {
	return (
		status === "complete" ||
		status === "error" ||
		status === "cancelled" ||
		status === "timeout"
	);
}

function isActiveStatus(status: DelegationStatus): boolean {
	return status === "registered" || status === "running";
}

function normalizeId(value: string): string {
	return assertSafeStorageSegment(value, "Delegation ID");
}

function parsePersistedStatus(raw: string | undefined): DelegationStatus {
	if (!raw) return "complete";
	if (raw === "registered") return "registered";
	if (raw === "running") return "running";
	if (raw === "complete") return "complete";
	if (raw === "error") return "error";
	if (raw === "cancelled") return "cancelled";
	if (raw === "timeout") return "timeout";
	return "complete";
}

class DelegationManager {
	private delegations: Map<string, DelegationRecord> = new Map();
	private delegationsBySession: Map<string, string> = new Map();
	private terminalWaiters: Map<
		string,
		{ promise: Promise<void>; resolve: () => void }
	> = new Map();
	private timeoutTimers: Map<string, ReturnType<typeof setTimeout>> = new Map();
	private client: OpencodeClient;
	private baseDir: string;
	private log: Logger;
	private maxRunTimeMs: number;
	private readPollIntervalMs: number;
	private terminalWaitGraceMs: number;
	private allCompleteQuietPeriodMs: number;
	private idGenerator: () => string;
	private metadataGenerator: typeof generateMetadata;
	private pendingByParent: Map<string, Set<string>> = new Map();
	private parentNotificationState: Map<string, ParentNotificationState> =
		new Map();
	private pendingNotifications: Map<string, string[]> = new Map();

	constructor(
		client: OpencodeClient,
		baseDir: string,
		log: Logger,
		options: DelegationManagerOptions = {},
	) {
		this.client = client;
		this.baseDir = baseDir;
		this.log = log;
		this.maxRunTimeMs = options.maxRunTimeMs ?? DEFAULT_MAX_RUN_TIME_MS;
		this.readPollIntervalMs =
			options.readPollIntervalMs ?? READ_POLL_INTERVAL_MS;
		this.terminalWaitGraceMs =
			options.terminalWaitGraceMs ?? TERMINAL_WAIT_GRACE_MS;
		this.allCompleteQuietPeriodMs =
			options.allCompleteQuietPeriodMs ?? ALL_COMPLETE_QUIET_PERIOD_MS;
		this.idGenerator = options.idGenerator ?? generateReadableId;
		this.metadataGenerator = options.metadataGenerator ?? generateMetadata;
	}

	/**
	 * Resolves the root session ID by walking up the parent chain.
	 */
	async getRootSessionID(sessionID: string): Promise<string> {
		let currentID = assertSafeStorageSegment(sessionID, "Session ID");
		const visited = new Set<string>();
		// Prevent infinite loops with max depth
		for (let depth = 0; depth < 10; depth++) {
			if (visited.has(currentID)) {
				throw new Error(
					"Failed to resolve root session: parent cycle detected",
				);
			}
			visited.add(currentID);
			try {
				const session = await this.client.session.get({
					path: { id: currentID },
				});

				if (!session.data?.parentID) {
					return currentID;
				}

				currentID = assertSafeStorageSegment(
					session.data.parentID,
					"Parent session ID",
				);
			} catch (error) {
				throw new Error(
					`Failed to resolve root session from "${currentID}": ${error instanceof Error ? error.message : String(error)}`,
				);
			}
		}
		throw new Error(
			"Failed to resolve root session: maximum traversal depth exceeded",
		);
	}

	/**
	 * Get the delegations directory for a session scope (root session)
	 */
	private async getDelegationsDir(sessionID: string): Promise<string> {
		const rootID = await this.getRootSessionID(sessionID);
		return path.join(this.baseDir, rootID);
	}

	/**
	 * Ensure the delegations directory exists
	 */
	private async ensureDelegationsDir(sessionID: string): Promise<string> {
		const dir = await this.getDelegationsDir(sessionID);
		await fs.mkdir(dir, { recursive: true });
		return dir;
	}

	private createTerminalWaiter(id: string): void {
		if (this.terminalWaiters.has(id)) return;

		let resolve: (() => void) | undefined;
		const promise = new Promise<void>((innerResolve) => {
			resolve = innerResolve;
		});

		if (!resolve) {
			throw new Error(
				`Failed to initialize terminal waiter for delegation ${id}`,
			);
		}

		this.terminalWaiters.set(id, { promise, resolve });
	}

	private resolveTerminalWaiter(id: string): void {
		const waiter = this.terminalWaiters.get(id);
		if (!waiter) return;
		waiter.resolve();
	}

	private clearTimeoutTimer(id: string): void {
		const timer = this.timeoutTimers.get(id);
		if (!timer) return;
		clearTimeout(timer);
		this.timeoutTimers.delete(id);
	}

	private scheduleTimeout(id: string): void {
		this.clearTimeoutTimer(id);
		const timer = setTimeout(() => {
			void this.handleTimeout(id);
		}, this.maxRunTimeMs + 5_000);
		this.timeoutTimers.set(id, timer);
	}

	private updateDelegation(
		id: string,
		mutate: (delegation: DelegationRecord, now: Date) => void,
	): DelegationRecord | undefined {
		const delegation = this.delegations.get(id);
		if (!delegation) return undefined;

		const now = new Date();
		mutate(delegation, now);
		delegation.updatedAt = now;
		return delegation;
	}

	private registerDelegation(input: {
		id: string;
		rootSessionID: string;
		sessionID: string;
		parentSessionID: string;
		parentMessageID: string;
		parentAgent: string;
		prompt: string;
		agent: string;
		artifactPath: string;
	}): DelegationRecord {
		if (!this.pendingByParent.has(input.parentSessionID)) {
			this.pendingByParent.set(input.parentSessionID, new Set());
			this.resetParentAllCompleteNotificationCycle(input.parentSessionID);
		}

		const parentNotificationState = this.getParentNotificationState(
			input.parentSessionID,
		);
		const notificationCycle = parentNotificationState.allCompleteCycle;
		const notificationCycleToken =
			parentNotificationState.allCompleteCycleToken;

		const now = new Date();
		const delegation: DelegationRecord = {
			id: input.id,
			rootSessionID: input.rootSessionID,
			sessionID: input.sessionID,
			parentSessionID: input.parentSessionID,
			parentMessageID: input.parentMessageID,
			parentAgent: input.parentAgent,
			prompt: input.prompt,
			agent: input.agent,
			notificationCycle,
			notificationCycleToken,
			status: "registered",
			createdAt: now,
			updatedAt: now,
			timeoutAt: new Date(now.getTime() + this.maxRunTimeMs),
			progress: {
				toolCalls: 0,
				lastUpdateAt: now,
				lastHeartbeatAt: now,
			},
			notification: {
				terminalNotificationCount: 0,
			},
			retrieval: {
				retrievalCount: 0,
			},
			artifact: {
				filePath: input.artifactPath,
			},
		};

		this.delegations.set(delegation.id, delegation);
		this.delegationsBySession.set(delegation.sessionID, delegation.id);
		this.createTerminalWaiter(delegation.id);
		this.pendingByParent.get(delegation.parentSessionID)?.add(delegation.id);

		return delegation;
	}

	private markStarted(id: string): DelegationRecord | undefined {
		return this.updateDelegation(id, (delegation, now) => {
			if (isTerminalStatus(delegation.status)) return;
			delegation.status = "running";
			delegation.startedAt = now;
			delegation.progress.lastUpdateAt = now;
			delegation.progress.lastHeartbeatAt = now;
		});
	}

	private markProgress(
		id: string,
		messageText?: string,
	): DelegationRecord | undefined {
		return this.updateDelegation(id, (delegation, now) => {
			if (isTerminalStatus(delegation.status)) return;
			if (delegation.status === "registered") {
				delegation.status = "running";
				delegation.startedAt = delegation.startedAt ?? now;
			}

			delegation.progress.lastUpdateAt = now;
			delegation.progress.lastHeartbeatAt = now;

			if (messageText) {
				delegation.progress.lastMessage = messageText;
				delegation.progress.lastMessageAt = now;
			}
		});
	}

	private markTerminal(
		id: string,
		status: DelegationTerminalStatus,
		error?: string,
	): { transitioned: boolean; delegation?: DelegationRecord } {
		const delegation = this.delegations.get(id);
		if (!delegation) return { transitioned: false };

		if (isTerminalStatus(delegation.status)) {
			return { transitioned: false, delegation };
		}

		const now = new Date();
		delegation.status = status;
		delegation.completedAt = now;
		delegation.updatedAt = now;
		if (error) {
			delegation.error = error;
		}

		const pending = this.pendingByParent.get(delegation.parentSessionID);
		if (pending) {
			pending.delete(delegation.id);
			if (pending.size === 0) {
				this.pendingByParent.delete(delegation.parentSessionID);
			}
		}

		this.clearTimeoutTimer(id);
		this.resolveTerminalWaiter(id);

		return { transitioned: true, delegation };
	}

	private markNotified(id: string): DelegationRecord | undefined {
		return this.updateDelegation(id, (delegation, now) => {
			delegation.notification.terminalNotifiedAt = now;
			delegation.notification.terminalNotificationCount += 1;
		});
	}

	private getParentNotificationState(
		parentSessionID: string,
	): ParentNotificationState {
		const existing = this.parentNotificationState.get(parentSessionID);
		if (existing) return existing;

		const initialized: ParentNotificationState = {
			allCompleteNotificationCount: 0,
			allCompleteCycle: 0,
			allCompleteCycleToken: this.buildAllCompleteCycleToken(
				parentSessionID,
				0,
			),
		};
		this.parentNotificationState.set(parentSessionID, initialized);
		return initialized;
	}

	private buildAllCompleteCycleToken(
		parentSessionID: string,
		cycle: number,
	): string {
		return `${parentSessionID}:${cycle}`;
	}

	private resetParentAllCompleteNotificationCycle(
		parentSessionID: string,
	): void {
		const state = this.getParentNotificationState(parentSessionID);
		this.cancelScheduledAllComplete(state);
		state.allCompleteCycle += 1;
		state.allCompleteCycleToken = this.buildAllCompleteCycleToken(
			parentSessionID,
			state.allCompleteCycle,
		);
		state.allCompleteNotifiedAt = undefined;
		state.allCompleteNotifiedCycle = undefined;
		state.allCompleteNotifiedCycleToken = undefined;
	}

	private cancelScheduledAllComplete(state: ParentNotificationState): void {
		if (state.allCompleteScheduledTimer) {
			clearTimeout(state.allCompleteScheduledTimer);
		}
		state.allCompleteScheduledTimer = undefined;
		state.allCompleteScheduledCycle = undefined;
		state.allCompleteScheduledCycleToken = undefined;
	}

	private areCycleTerminalNotificationsComplete(
		parentSessionID: string,
		cycleToken: string,
	): boolean {
		let cycleDelegationCount = 0;

		for (const delegation of this.delegations.values()) {
			if (delegation.parentSessionID !== parentSessionID) continue;
			if (delegation.notificationCycleToken !== cycleToken) continue;

			cycleDelegationCount += 1;
			if (!delegation.notification.terminalNotifiedAt) {
				return false;
			}
		}

		return cycleDelegationCount > 0;
	}

	private scheduleAllCompleteForParent(
		parentSessionID: string,
		parentAgent: string,
	): void {
		const state = this.getParentNotificationState(parentSessionID);
		const cycle = state.allCompleteCycle;
		const cycleToken = state.allCompleteCycleToken;
		if (
			!this.areCycleTerminalNotificationsComplete(parentSessionID, cycleToken)
		)
			return;

		if (state.allCompleteNotifiedCycleToken === cycleToken) return;
		if (state.allCompleteScheduledCycleToken === cycleToken) return;

		this.cancelScheduledAllComplete(state);

		state.allCompleteScheduledCycle = cycle;
		state.allCompleteScheduledCycleToken = cycleToken;
		state.allCompleteScheduledTimer = setTimeout(() => {
			void this.dispatchScheduledAllComplete(
				parentSessionID,
				parentAgent,
				cycle,
				cycleToken,
			);
		}, this.allCompleteQuietPeriodMs);
	}

	private async dispatchScheduledAllComplete(
		parentSessionID: string,
		parentAgent: string,
		cycle: number,
		cycleToken: string,
	): Promise<void> {
		const state = this.getParentNotificationState(parentSessionID);

		if (state.allCompleteScheduledCycleToken !== cycleToken) return;

		this.cancelScheduledAllComplete(state);

		if (state.allCompleteCycleToken !== cycleToken) return;
		if (
			!this.areCycleTerminalNotificationsComplete(parentSessionID, cycleToken)
		)
			return;
		if (state.allCompleteNotifiedCycleToken === cycleToken) return;

		const deliveryStatus = await this.sendParentNotification(
			parentSessionID,
			parentAgent,
			this.buildAllCompleteNotification(parentSessionID, cycle, cycleToken),
			false,
		);

		if (state.allCompleteCycleToken !== cycleToken) return;
		if (
			!this.areCycleTerminalNotificationsComplete(parentSessionID, cycleToken)
		)
			return;

		state.allCompleteNotifiedAt = new Date();
		state.allCompleteNotificationCount += 1;
		state.allCompleteNotifiedCycle = cycle;
		state.allCompleteNotifiedCycleToken = cycleToken;

		await this.debugLog(
			`all-complete notification ${deliveryStatus} for ${parentSessionID} cycle=${cycleToken}`,
		);
	}

	private queuePendingNotification(
		parentSessionID: string,
		notification: string,
	): void {
		const pending = this.pendingNotifications.get(parentSessionID) ?? [];
		pending.push(notification);
		this.pendingNotifications.set(parentSessionID, pending);
	}

	private async sendParentNotification(
		parentSessionID: string,
		parentAgent: string,
		notification: string,
		noReply: boolean,
	): Promise<"sent" | "queued" | "timed-out"> {
		const session = this.client.session;
		let timeout: ReturnType<typeof setTimeout> | undefined;

		try {
			await this.debugLog(
				`parent notification sending for ${parentSessionID} noReply=${noReply} async=${Boolean(
					session.promptAsync,
				)}`,
			);

			const result = await Promise.race<"sent" | "timed-out">([
				session
					.promptAsync({
						path: { id: parentSessionID },
						body: {
							noReply,
							agent: parentAgent,
							parts: [{ type: "text", text: notification }],
						},
					})
					.then(() => "sent" as const),
				new Promise<"timed-out">((resolve) => {
					timeout = setTimeout(
						() => resolve("timed-out"),
						PARENT_NOTIFICATION_TIMEOUT_MS,
					);
				}),
			]);

			if (result === "timed-out") {
				await this.debugLog(
					`parent notification timed out for ${parentSessionID} after ${PARENT_NOTIFICATION_TIMEOUT_MS}ms`,
				);
			}

			return result;
		} catch (error) {
			this.queuePendingNotification(parentSessionID, notification);
			await this.debugLog(
				`parent notification queued for ${parentSessionID}: ${
					error instanceof Error ? error.message : "Unknown error"
				}`,
			);
			return "queued";
		} finally {
			if (timeout) clearTimeout(timeout);
		}
	}

	injectPendingNotificationsIntoChatMessage(
		output: { parts?: Array<{ type: string; text?: string }> },
		sessionID: string,
	): void {
		const pending = this.pendingNotifications.get(sessionID);
		if (!pending || pending.length === 0) return;

		this.pendingNotifications.delete(sessionID);
		const notificationText = pending.join("\n\n");
		const parts = output.parts ?? [];
		const firstTextPart = parts.find((part) => part.type === "text");

		if (firstTextPart) {
			firstTextPart.text = `${notificationText}\n\n${firstTextPart.text ?? ""}`;
			output.parts = parts;
			return;
		}

		output.parts = [{ type: "text", text: notificationText }, ...parts];
	}

	private markRetrieved(
		id: string,
		readerSessionID: string,
	): DelegationRecord | undefined {
		return this.updateDelegation(id, (delegation, now) => {
			delegation.retrieval.retrievedAt = now;
			delegation.retrieval.retrievalCount += 1;
			delegation.retrieval.lastReaderSessionID = readerSessionID;
		});
	}

	private hasUnreadCompletion(delegation: DelegationRecord): boolean {
		if (!isTerminalStatus(delegation.status)) return false;
		if (!delegation.notification.terminalNotifiedAt) return false;
		if (!delegation.completedAt) return false;

		if (!delegation.retrieval.retrievedAt) return true;
		return (
			delegation.retrieval.retrievedAt.getTime() <
			delegation.completedAt.getTime()
		);
	}

	private async waitForTerminal(
		id: string,
		timeoutMs: number,
	): Promise<"terminal" | "timeout"> {
		const delegation = this.delegations.get(id);
		if (!delegation) return "timeout";
		if (isTerminalStatus(delegation.status)) return "terminal";

		const waiter = this.terminalWaiters.get(id);
		if (!waiter) return "timeout";

		let timer: ReturnType<typeof setTimeout> | undefined;
		try {
			const result = await Promise.race<"terminal" | "timeout">([
				waiter.promise.then(() => "terminal"),
				new Promise<"timeout">((resolve) => {
					timer = setTimeout(() => resolve("timeout"), timeoutMs);
				}),
			]);
			return result;
		} finally {
			if (timer) clearTimeout(timer);
		}
	}

	private async generateUniqueDelegationId(
		artifactDir: string,
	): Promise<string> {
		for (let attempt = 0; attempt < 20; attempt++) {
			const candidate = this.idGenerator();
			if (this.delegations.has(candidate)) continue;

			const candidatePath = path.join(artifactDir, `${candidate}.md`);
			try {
				await fs.access(candidatePath);
			} catch {
				return candidate;
			}
		}

		throw new Error(
			"Failed to generate unique delegation ID after 20 attempts",
		);
	}

	private getDelegationBySession(
		sessionID: string,
	): DelegationRecord | undefined {
		const delegationId = this.delegationsBySession.get(sessionID);
		if (!delegationId) return undefined;
		return this.delegations.get(delegationId);
	}

	private isVisibleToSession(
		delegation: DelegationRecord,
		rootSessionID: string,
	): boolean {
		return delegation.rootSessionID === rootSessionID;
	}

	private buildTerminalNotification(
		delegation: DelegationRecord,
		remainingCount: number,
	): string {
		const lines = [
			"<task-notification>",
			`<task-id>${delegation.id}</task-id>`,
			`<status>${delegation.status}</status>`,
			`<summary>Background agent ${delegation.status}: ${delegation.title || delegation.id}</summary>`,
			delegation.title ? `<title>${delegation.title}</title>` : "",
			delegation.description
				? `<description>${delegation.description}</description>`
				: "",
			delegation.error ? `<error>${delegation.error}</error>` : "",
			`<artifact>${delegation.artifact.filePath}</artifact>`,
			`<retrieval>Use delegation_read("${delegation.id}") for full output.</retrieval>`,
			remainingCount > 0 ? `<remaining>${remainingCount}</remaining>` : "",
			"</task-notification>",
		];

		return lines.filter((line) => line.length > 0).join("\n");
	}

	private buildAllCompleteNotification(
		parentSessionID: string,
		cycle: number,
		cycleToken: string,
	): string {
		// cycle-token is a boundary watermark.
		// Receivers should ignore all-complete payloads whose token is older than
		// the latest known registration cycle for this parent session.
		return [
			"<task-notification>",
			"<type>all-complete</type>",
			"<status>completed</status>",
			"<summary>All delegations complete.</summary>",
			`<parent-session-id>${parentSessionID}</parent-session-id>`,
			`<cycle>${cycle}</cycle>`,
			`<cycle-token>${cycleToken}</cycle-token>`,
			"</task-notification>",
		].join("\n");
	}

	private buildDeterministicTerminalReadResponse(
		delegation: DelegationRecord,
	): string {
		const lines = [
			`Delegation ID: ${delegation.id}`,
			`Status: ${delegation.status}`,
			`Agent: ${delegation.agent}`,
			`Started: ${delegation.startedAt?.toISOString() || delegation.createdAt.toISOString()}`,
			`Completed: ${delegation.completedAt?.toISOString() || "N/A"}`,
			`Artifact: ${delegation.artifact.filePath}`,
		];

		if (delegation.title) lines.push(`Title: ${delegation.title}`);
		if (delegation.description)
			lines.push(`Description: ${delegation.description}`);
		if (delegation.error) lines.push(`Error: ${delegation.error}`);

		lines.push(
			`\nUse delegation_read("${delegation.id}") again after persistence completes.`,
		);
		return lines.join("\n");
	}

	private async readPersistedArtifact(
		filePath: string,
	): Promise<string | null> {
		try {
			return await fs.readFile(filePath, "utf8");
		} catch {
			return null;
		}
	}

	private async waitForPersistedArtifact(
		filePath: string,
		maxWaitMs: number,
	): Promise<string | null> {
		const start = Date.now();
		while (Date.now() - start < maxWaitMs) {
			const content = await this.readPersistedArtifact(filePath);
			if (content !== null) return content;
			await new Promise((resolve) =>
				setTimeout(resolve, this.readPollIntervalMs),
			);
		}

		return null;
	}

	private async resolveDelegationResult(
		delegation: DelegationRecord,
	): Promise<string> {
		if (delegation.status === "error") {
			return `Error: ${delegation.error || "Delegation failed."}`;
		}

		if (delegation.status === "cancelled") {
			return "Delegation was cancelled before completion.";
		}

		if (delegation.status === "timeout") {
			const partial = await this.getResult(delegation);
			return `${partial}\n\n[TIMEOUT REACHED]`;
		}

		return await this.getResult(delegation);
	}

	private async finalizeDelegation(
		delegationId: string,
		status: DelegationTerminalStatus,
		error?: string,
	): Promise<void> {
		const { transitioned, delegation } = this.markTerminal(
			delegationId,
			status,
			error,
		);
		if (!transitioned || !delegation) return;

		await this.debugLog(
			`finalizeDelegation(${delegation.id}, ${status}) started`,
		);

		const resolvedResult = await this.resolveDelegationResult(delegation);
		delegation.result = resolvedResult;

		if (resolvedResult.trim().length > 0) {
			const metadata = await this.metadataGenerator(
				this.client,
				resolvedResult,
				delegation.sessionID,
				(msg) => this.debugLog(msg),
			);
			delegation.title = metadata.title;
			delegation.description = metadata.description;
		}

		await this.persistOutput(delegation, resolvedResult);
		await this.notifyParent(delegation.id);
	}

	private async notifyParent(delegationId: string): Promise<void> {
		try {
			const delegation = this.delegations.get(delegationId);
			if (!delegation) return;
			if (!isTerminalStatus(delegation.status)) return;
			if (delegation.notification.terminalNotifiedAt) {
				await this.debugLog(
					`notifyParent skipped for ${delegation.id}; already notified`,
				);
				return;
			}

			const remainingCount = this.getPendingCount(delegation.parentSessionID);
			const terminalNotification = this.buildTerminalNotification(
				delegation,
				remainingCount,
			);

			const deliveryStatus = await this.sendParentNotification(
				delegation.parentSessionID,
				delegation.parentAgent,
				terminalNotification,
				true,
			);

			this.markNotified(delegation.id);
			this.scheduleAllCompleteForParent(
				delegation.parentSessionID,
				delegation.parentAgent,
			);

			await this.debugLog(
				`notifyParent ${deliveryStatus} for ${delegation.id} (remaining=${remainingCount}, status=${delegation.status})`,
			);
		} catch (error) {
			await this.debugLog(
				`notifyParent failed for ${delegationId}: ${error instanceof Error ? error.message : "Unknown error"}`,
			);
		}
	}

	/**
	 * Delegate a task to an agent
	 */
	async delegate(input: DelegateInput): Promise<DelegationRecord> {
		// Validate agent exists before creating session
		const agentsResult = await this.client.app.agents({});
		const agents = (agentsResult.data ?? []) as {
			name: string;
			description?: string;
			mode?: string;
		}[];
		const validAgent = agents.find((a) => a.name === input.agent);

		if (!validAgent) {
			const available = agents
				.filter((a) => a.mode === "subagent" || a.mode === "all" || !a.mode)
				.map((a) => `• ${a.name}${a.description ? ` - ${a.description}` : ""}`)
				.join("\n");

			throw new Error(
				`Agent "${input.agent}" not found.\n\nAvailable agents:\n${available || "(none)"}`,
			);
		}
		if (validAgent.mode !== "subagent") {
			throw new Error(
				`Agent "${input.agent}" is not an installed sub-agent and cannot run through delegate.`,
			);
		}

		// Check if agent is read-only (Early Exit + Fail Fast)
		const { isReadOnly } = await parseAgentWriteCapability(
			this.client,
			input.agent,
			this.log,
		);
		if (!isReadOnly) {
			throw new Error(
				`Agent "${input.agent}" is write-capable and requires the native \`task\` tool for proper undo/branching support.\n\n` +
					`Use \`task\` instead of \`delegate\` for write-capable agents.\n\n` +
					`Strict read-only sub-agents use \`delegate\`.\n` +
					`Write-capable sub-agents use \`task\` from a managed worktree.`,
			);
		}

		const artifactDir = await this.ensureDelegationsDir(input.parentSessionID);
		const rootSessionID = await this.getRootSessionID(input.parentSessionID);
		const stableId = await this.generateUniqueDelegationId(artifactDir);
		const artifactPath = path.join(artifactDir, `${stableId}.md`);

		await this.debugLog(`delegate() called, generated stable ID: ${stableId}`);

		// Create isolated session for delegation
		const sessionResult = await this.client.session.create({
			body: {
				title: `Delegation: ${stableId}`,
				parentID: input.parentSessionID,
			},
		});

		await this.debugLog(
			`session.create result: ${JSON.stringify(sessionResult.data)}`,
		);

		if (!sessionResult.data?.id) {
			throw new Error("Failed to create delegation session");
		}

		const delegation = this.registerDelegation({
			id: stableId,
			rootSessionID,
			sessionID: sessionResult.data.id,
			parentSessionID: input.parentSessionID,
			parentMessageID: input.parentMessageID,
			parentAgent: input.parentAgent,
			prompt: input.prompt,
			agent: input.agent,
			artifactPath,
		});

		await this.debugLog(
			`Registered delegation ${delegation.id} before execution`,
		);
		this.scheduleTimeout(delegation.id);
		this.markStarted(delegation.id);

		// Fire the prompt (using prompt() instead of promptAsync() to properly initialize agent loop)
		// Agent param is critical for MCP tools - tells OpenCode which agent's config to use
		// Anti-recursion: disable nested delegations and state-modifying tools via tools config
		this.client.session
			.prompt({
				path: { id: delegation.sessionID },
				body: {
					agent: input.agent,
					parts: [{ type: "text", text: input.prompt }],
					tools: {
						task: false,
						delegate: false,
						todowrite: false,
						plan_save: false,
					},
				},
			})
			.then(() => {
				void this.finalizeDelegation(delegation.id, "complete");
			})
			.catch((error: Error) => {
				void this.finalizeDelegation(delegation.id, "error", error.message);
			});

		return delegation;
	}

	/**
	 * Handle delegation timeout
	 */
	private async handleTimeout(delegationId: string): Promise<void> {
		const delegation = this.delegations.get(delegationId);
		if (!delegation || isTerminalStatus(delegation.status)) return;

		await this.debugLog(`handleTimeout for delegation ${delegation.id}`);

		// Try to cancel the session
		try {
			await this.client.session.delete({
				path: { id: delegation.sessionID },
			});
		} catch {
			// Ignore
		}

		await this.finalizeDelegation(
			delegation.id,
			"timeout",
			`Delegation timed out after ${this.maxRunTimeMs / 1000}s`,
		);
	}

	/**
	 * Handle session.idle event - called when a session becomes idle
	 */
	async handleSessionIdle(sessionID: string): Promise<void> {
		const delegation = this.findBySession(sessionID);
		if (!delegation || isTerminalStatus(delegation.status)) return;

		await this.debugLog(`handleSessionIdle for delegation ${delegation.id}`);
		await this.finalizeDelegation(delegation.id, "complete");
	}

	/**
	 * Get the result from a delegation's session
	 */
	private async getResult(delegation: DelegationRecord): Promise<string> {
		try {
			const messages = await this.client.session.messages({
				path: { id: delegation.sessionID },
			});

			const messageData = messages.data as SessionMessageItem[] | undefined;

			if (!messageData || messageData.length === 0) {
				await this.debugLog(
					`getResult: No messages found for session ${delegation.sessionID}`,
				);
				return `Delegation "${delegation.description}" completed but produced no output.`;
			}

			await this.debugLog(
				`getResult: Found ${messageData.length} messages. Roles: ${messageData.map((m) => m.info.role).join(", ")}`,
			);

			// Find the last message from the assistant/model
			const isAssistantMessage = (
				m: SessionMessageItem,
			): m is AssistantSessionMessageItem => m.info.role === "assistant";

			const assistantMessages = messageData.filter(isAssistantMessage);

			if (assistantMessages.length === 0) {
				await this.debugLog(
					`getResult: No assistant messages found in ${JSON.stringify(messageData.map((m) => ({ role: m.info.role, keys: Object.keys(m) })))}`,
				);
				return `Delegation "${delegation.description}" completed but produced no assistant response.`;
			}

			const lastMessage = assistantMessages[assistantMessages.length - 1];

			// Extract text parts from the message
			const isTextPart = (p: Part): p is TextPart => p.type === "text";
			const textParts = lastMessage.parts.filter(isTextPart);

			if (textParts.length === 0) {
				await this.debugLog(
					`getResult: No text parts found in message: ${JSON.stringify(lastMessage)}`,
				);
				return `Delegation "${delegation.description}" completed but produced no text content.`;
			}

			return textParts.map((p) => p.text).join("\n");
		} catch (error) {
			await this.debugLog(
				`getResult error: ${error instanceof Error ? error.message : "Unknown error"}`,
			);
			return `Delegation "${delegation.description}" completed but result could not be retrieved: ${
				error instanceof Error ? error.message : "Unknown error"
			}`;
		}
	}

	/**
	 * Persist delegation output to storage
	 */
	private async persistOutput(
		delegation: DelegationRecord,
		content: string,
	): Promise<void> {
		try {
			// Use title/description if available (generated by small model), otherwise fallback
			const title = delegation.title || delegation.id;
			const description =
				delegation.description || "(No description generated)";

			const header = `# ${title}

${description}

**ID:** ${delegation.id}
**Agent:** ${delegation.agent}
**Status:** ${delegation.status}
**Session:** ${delegation.sessionID}
**Started:** ${(delegation.startedAt || delegation.createdAt).toISOString()}
**Completed:** ${delegation.completedAt?.toISOString() || "N/A"}

---

`;
			await fs.writeFile(
				delegation.artifact.filePath,
				header + content,
				"utf8",
			);

			const stats = await fs.stat(delegation.artifact.filePath);
			this.updateDelegation(delegation.id, (record, now) => {
				record.artifact.persistedAt = now;
				record.artifact.byteLength = stats.size;
				record.artifact.persistError = undefined;
			});

			await this.debugLog(
				`Persisted output to ${delegation.artifact.filePath}`,
			);
		} catch (error) {
			this.updateDelegation(delegation.id, (record) => {
				record.artifact.persistError =
					error instanceof Error ? error.message : "Unknown persistence error";
			});
			await this.debugLog(
				`Failed to persist output: ${error instanceof Error ? error.message : "Unknown error"}`,
			);
		}
	}

	/**
	 * Read a delegation's output by ID. Blocks if the delegation is still running.
	 */
	async readOutput(sessionID: string, id: string): Promise<string> {
		const normalizedId = normalizeId(id);
		if (!normalizedId) {
			throw new Error("Delegation ID is required");
		}

		const rootSessionID = await this.getRootSessionID(sessionID);
		let delegation = this.delegations.get(normalizedId);
		if (delegation && !this.isVisibleToSession(delegation, rootSessionID)) {
			delegation = undefined;
		}

		const fallbackFilePath = path.join(
			await this.getDelegationsDir(sessionID),
			`${normalizedId}.md`,
		);

		const immediateArtifactPath =
			delegation?.artifact.filePath || fallbackFilePath;
		const immediateRead = await this.readPersistedArtifact(
			immediateArtifactPath,
		);
		if (immediateRead !== null) {
			if (delegation) this.markRetrieved(delegation.id, sessionID);
			return immediateRead;
		}

		if (!delegation) {
			throw new Error(
				`Delegation "${normalizedId}" not found.\n\nUse delegation_list() to see available delegations.`,
			);
		}

		if (isActiveStatus(delegation.status)) {
			const remainingMs = Math.max(
				delegation.timeoutAt.getTime() - Date.now() + this.terminalWaitGraceMs,
				this.readPollIntervalMs,
			);

			await this.debugLog(
				`readOutput: waiting up to ${remainingMs}ms for delegation ${delegation.id} to reach terminal state`,
			);

			const waitResult = await this.waitForTerminal(delegation.id, remainingMs);
			if (waitResult === "timeout" && isActiveStatus(delegation.status)) {
				await this.handleTimeout(delegation.id);
			}
		}

		if (isTerminalStatus(delegation.status)) {
			const delayedPersisted = await this.waitForPersistedArtifact(
				delegation.artifact.filePath,
				Math.max(this.readPollIntervalMs * 8, 500),
			);
			if (delayedPersisted !== null) {
				this.markRetrieved(delegation.id, sessionID);
				return delayedPersisted;
			}
		}

		const persisted = await this.readPersistedArtifact(
			delegation.artifact.filePath,
		);
		if (persisted !== null) {
			this.markRetrieved(delegation.id, sessionID);
			return persisted;
		}

		if (isTerminalStatus(delegation.status)) {
			return this.buildDeterministicTerminalReadResponse(delegation);
		}

		return `Delegation "${delegation.id}" is still running. You will receive a <task-notification> when it reaches a terminal state.`;
	}

	/**
	 * List all delegations for a session
	 */
	async listDelegations(sessionID: string): Promise<DelegationListItem[]> {
		const rootSessionID = await this.getRootSessionID(sessionID);
		const results: DelegationListItem[] = [];

		// Add in-memory delegations in this root session scope
		for (const delegation of this.delegations.values()) {
			if (!this.isVisibleToSession(delegation, rootSessionID)) continue;

			results.push({
				id: delegation.id,
				status: delegation.status,
				title: delegation.title || delegation.id,
				description:
					delegation.description ||
					(delegation.status === "running" || delegation.status === "registered"
						? "(running)"
						: "(no description)"),
				agent: delegation.agent,
				unread: this.hasUnreadCompletion(delegation),
			});
		}

		// Check filesystem for persisted delegations
		try {
			const dir = await this.getDelegationsDir(rootSessionID);
			const files = await fs.readdir(dir);

			for (const file of files) {
				if (file.endsWith(".md")) {
					const id = file.replace(".md", "");
					// Deduplicate: prioritize in-memory status
					if (!results.find((r) => r.id === id)) {
						// Try to read title, agent, description from file
						let title = "(loaded from storage)";
						let description = "";
						let agent: string | undefined;
						let status: DelegationStatus = "complete";
						try {
							const filePath = path.join(dir, file);
							const content = await fs.readFile(filePath, "utf8");
							const titleMatch = content.match(/^# (.+)$/m);
							if (titleMatch) title = titleMatch[1];
							const agentMatch = content.match(/^\*\*Agent:\*\* (.+)$/m);
							if (agentMatch) agent = agentMatch[1];
							const statusMatch = content.match(/^\*\*Status:\*\* (.+)$/m);
							status = parsePersistedStatus(statusMatch?.[1]?.trim());
							// Get first paragraph after title as description
							const lines = content.split("\n");
							if (lines.length > 2 && lines[2]) {
								description = lines[2].slice(0, 150);
							}
						} catch {
							// Ignore read errors
						}
						results.push({
							id,
							status,
							title,
							description,
							agent,
							unread: false,
						});
					}
				}
			}
		} catch {
			// Directory may not exist yet
		}

		results.sort((a, b) => a.id.localeCompare(b.id));
		return results;
	}

	/**
	 * Delete a delegation by id (cancels if running, removes from storage)
	 * Used internally for cleanup (timeout, etc.)
	 */
	async deleteDelegation(sessionID: string, id: string): Promise<boolean> {
		const normalizedId = normalizeId(id);
		const delegation = this.delegations.get(normalizedId);

		if (delegation) {
			if (isActiveStatus(delegation.status)) {
				try {
					await this.client.session.delete({
						path: { id: delegation.sessionID },
					});
				} catch {
					// Session may already be deleted
				}
				this.markTerminal(
					delegation.id,
					"cancelled",
					"Delegation deleted by cleanup",
				);
			}

			this.clearTimeoutTimer(delegation.id);
			this.terminalWaiters.delete(delegation.id);
			this.delegationsBySession.delete(delegation.sessionID);
			this.delegations.delete(delegation.id);
		}

		// Remove from filesystem
		try {
			const dir = await this.getDelegationsDir(sessionID);
			const filePath = path.join(dir, `${normalizedId}.md`);
			await fs.unlink(filePath);
			return true;
		} catch {
			return false;
		}
	}

	/**
	 * Find a delegation by its session ID
	 */
	findBySession(sessionID: string): DelegationRecord | undefined {
		return this.getDelegationBySession(sessionID);
	}

	/**
	 * Handle message events for progress tracking
	 */
	handleMessageEvent(sessionID: string, messageText?: string): void {
		const delegation = this.findBySession(sessionID);
		if (!delegation) return;
		this.markProgress(delegation.id, messageText);
	}

	/**
	 * Get count of pending delegations for a parent session
	 */
	getPendingCount(parentSessionID: string): number {
		const pendingSet = this.pendingByParent.get(parentSessionID);
		if (!pendingSet) return 0;
		return Array.from(pendingSet).filter((id) => {
			const delegation = this.delegations.get(id);
			return delegation ? isActiveStatus(delegation.status) : false;
		}).length;
	}

	/**
	 * Get all currently running delegations (in-memory only)
	 */
	getRunningDelegations(rootSessionID?: string): DelegationRecord[] {
		return Array.from(this.delegations.values()).filter((delegation) => {
			if (rootSessionID && delegation.rootSessionID !== rootSessionID)
				return false;
			return isActiveStatus(delegation.status);
		});
	}

	getUnreadCompletedDelegations(
		rootSessionID: string,
		limit = 10,
	): DelegationRecord[] {
		return Array.from(this.delegations.values())
			.filter((delegation) => delegation.rootSessionID === rootSessionID)
			.filter((delegation) => this.hasUnreadCompletion(delegation))
			.sort((a, b) => {
				const aTime = a.completedAt?.getTime() || 0;
				const bTime = b.completedAt?.getTime() || 0;
				return bTime - aTime;
			})
			.slice(0, limit);
	}

	/**
	 * Get recent completed delegations for compaction injection
	 */
	async getRecentCompletedDelegations(
		sessionID: string,
		limit: number = 10,
	): Promise<DelegationListItem[]> {
		const all = await this.listDelegations(sessionID);
		return all.filter((d) => isTerminalStatus(d.status)).slice(-limit);
	}

	/**
	 * Log debug messages
	 */
	async debugLog(msg: string): Promise<void> {
		// Only log if debug is enabled (could be env var or static const)
		// For now, mirroring previous behavior but writing to the new baseDir/debug.log
		const timestamp = new Date().toISOString();
		const line = `${timestamp}: ${msg}\n`;
		const debugFile = path.join(this.baseDir, "background-agents-debug.log");

		try {
			await fs.appendFile(debugFile, line, "utf8");
		} catch {
			// Ignore errors, try to ensure dir once if it fails?
			// Simpler to just ignore for debug logs
		}
	}
}

// ==========================================
// TOOL CREATORS
// ==========================================

interface DelegateArgs {
	prompt: string;
	agent: string;
}

function createDelegate(manager: DelegationManager): ReturnType<typeof tool> {
	return tool({
		description: `Delegate a task to a strict read-only agent. Returns immediately with a readable ID.

Use this for:
- Codebase exploration with "explore"
- External research with "researcher"
- Independent review with "reviewer"
- Parallel work that can run in background
- Any task where you want persistent, retrievable output

Use native "task" only for write-capable "coder" and "scribe" agents. Never use "task" for "reviewer".

On completion, a notification will arrive with the ID and terminal summary.
Use \`delegation_read\` with the ID to retrieve full persisted output (including after compaction).`,
		args: {
			prompt: tool.schema
				.string()
				.describe(
					"The full detailed prompt for the agent. Must be in English.",
				),
			agent: tool.schema
				.string()
				.describe(
					'Strict read-only agent. Use "explore", "researcher", or "reviewer". Never use native "task" for these agents.',
				),
		},
		async execute(args: DelegateArgs, toolCtx: ToolContext): Promise<string> {
			if (!toolCtx?.sessionID) {
				return "❌ delegate requires sessionID. This is a system error.";
			}
			if (!toolCtx?.messageID) {
				return "❌ delegate requires messageID. This is a system error.";
			}
			if (!DELEGATION_ORCHESTRATORS.has(toolCtx.agent)) {
				return `❌ Agent '${toolCtx.agent}' is not authorized to launch background delegations.`;
			}

			try {
				const delegation = await manager.delegate({
					parentSessionID: toolCtx.sessionID,
					parentMessageID: toolCtx.messageID,
					parentAgent: toolCtx.agent,
					prompt: args.prompt,
					agent: args.agent,
				});

				// Get total active count for this parent session
				const pendingSet = manager.getPendingCount(toolCtx.sessionID);
				const totalActive = pendingSet;

				let response = `Delegation started: ${delegation.id}\nAgent: ${args.agent}`;
				if (totalActive > 1) {
					response += `\n\n${totalActive} delegations now active.`;
				}
				response += `\nYou WILL be notified when ${totalActive > 1 ? "ALL complete" : "complete"}. Do NOT poll.`;

				return response;
			} catch (error) {
				// Return validation errors as guidance, not exceptions
				return `❌ Delegation failed:\n\n${error instanceof Error ? error.message : "Unknown error"}`;
			}
		},
	});
}

function createDelegationRead(
	manager: DelegationManager,
): ReturnType<typeof tool> {
	return tool({
		description: `Read the output of a delegation by its ID.
Use this to retrieve results from delegated tasks if the inline notification was lost during compaction.`,
		args: {
			id: tool.schema
				.string()
				.describe("The delegation ID (e.g., 'elegant-blue-tiger')"),
		},
		async execute(args: { id: string }, toolCtx: ToolContext): Promise<string> {
			if (!toolCtx?.sessionID) {
				return "❌ delegation_read requires sessionID. This is a system error.";
			}

			return await manager.readOutput(toolCtx.sessionID, args.id);
		},
	});
}

function createDelegationList(
	manager: DelegationManager,
): ReturnType<typeof tool> {
	return tool({
		description: `List all delegations for the current session.
Shows both running and completed delegations.`,
		args: {},
		async execute(
			_args: Record<string, never>,
			toolCtx: ToolContext,
		): Promise<string> {
			if (!toolCtx?.sessionID) {
				return "❌ delegation_list requires sessionID. This is a system error.";
			}

			const delegations = await manager.listDelegations(toolCtx.sessionID);

			if (delegations.length === 0) {
				return "No delegations found for this session.";
			}

			const lines = delegations.map((d) => {
				const titlePart = d.title ? ` | ${d.title}` : "";
				const unreadPart = d.unread ? " [unread]" : "";
				const descPart = d.description ? `\n  → ${d.description}` : "";
				return `- **${d.id}**${titlePart} [${d.status}]${unreadPart}${descPart}`;
			});

			return `## Delegations\n\n${lines.join("\n")}`;
		},
	});
}

// ==========================================
// DELEGATION RULES (injected into system prompt)
// ==========================================

const DELEGATION_RULES = `<task-notification>
<delegation-system>

## Async Delegation

You have tools for parallel background work:
- \`delegate(prompt, agent)\` - Launch task, returns ID immediately
- \`delegation_read(id)\` - Retrieve completed result
- \`delegation_list()\` - List delegations (use sparingly)

## Delegation Routing

Agents route based on their permissions:

| Agent Type | Tool | Why |
|------------|------|-----|
| \`explore\`, \`researcher\`, \`reviewer\` | \`delegate\` | Strict read-only background session |
| \`coder\`, \`scribe\` | \`task\` | Write-capable native task inside a managed worktree |

**Strict read-only sub-agents** deny edit, write, bash, task, delegate, plan writes, and worktree mutation without allow/ask exceptions.
**Write-capable sub-agents** have at least one direct or indirect mutation route.

## How It Works

1. For \`explore\`, \`researcher\`, or \`reviewer\`: Call \`delegate\` with detailed prompt
2. For \`coder\` or \`scribe\`: Call \`task\` with detailed prompt
3. Continue productive work while it runs
4. Receive notification when complete
5. Call \`delegation_read(id)\` to retrieve results

## Critical Constraints

**NEVER poll \`delegation_list\` to check completion.**
You WILL be notified via \`<task-notification>\`. Polling wastes tokens.

**NEVER wait idle.** Always have productive work while delegations run.

**Using wrong tool will fail fast with guidance.**

</delegation-system>
</task-notification>`;

// ==========================================
// COMPACTION CONTEXT FORMATTING
// ==========================================

interface DelegationForContext {
	id: string;
	agent?: string;
	title?: string;
	description?: string;
	status: DelegationStatus;
	startedAt?: Date;
	completedAt?: Date;
	lastHeartbeatAt?: Date;
	prompt?: string;
}

/**
 * Format delegation context for injection during compaction.
 * Includes running delegations with notification reminder (only when running exist),
 * and recent completed delegations with full descriptions.
 */
function formatDelegationContext(
	running: DelegationForContext[],
	unreadCompleted: DelegationForContext[],
): string {
	const sections: string[] = ["<delegation-context>"];

	// Running delegations (if any)
	if (running.length > 0) {
		sections.push("## Running Delegations");
		sections.push("");
		for (const d of running) {
			sections.push(`### \`${d.id}\`${d.agent ? ` (${d.agent})` : ""}`);
			if (d.startedAt) {
				sections.push(`**Started:** ${d.startedAt.toISOString()}`);
			}
			if (d.lastHeartbeatAt) {
				sections.push(`**Last heartbeat:** ${d.lastHeartbeatAt.toISOString()}`);
			}
			if (d.prompt) {
				const truncatedPrompt =
					d.prompt.length > 200 ? `${d.prompt.slice(0, 200)}...` : d.prompt;
				sections.push(`**Prompt:** ${truncatedPrompt}`);
			}
			sections.push("");
		}

		// Only include reminder when there ARE running delegations
		sections.push(
			"> **Note:** You WILL be notified via `<task-notification>` when delegations complete.",
		);
		sections.push(
			"> Do NOT poll `delegation_list` - continue productive work.",
		);
		sections.push("");
	}

	// Unread completed delegations (recent)
	if (unreadCompleted.length > 0) {
		sections.push("## Unread Completed Delegations");
		sections.push("");
		for (const d of unreadCompleted) {
			const statusEmoji =
				d.status === "complete"
					? "✅"
					: d.status === "error"
						? "❌"
						: d.status === "timeout"
							? "⏱️"
							: "🚫";
			sections.push(`### ${statusEmoji} \`${d.id}\``);
			sections.push(`**Title:** ${d.title || "(no title)"}`);
			sections.push(`**Status:** ${d.status}`);
			sections.push(`**Description:** ${d.description || "(no description)"}`);
			if (d.completedAt) {
				sections.push(`**Completed:** ${d.completedAt.toISOString()}`);
			}
			sections.push(`**Retrieve:** \`delegation_read("${d.id}")\``);
			sections.push("");
		}
		sections.push(
			"> These are unread terminal delegations carried forward through compaction.",
		);
		sections.push("");
	}

	sections.push("## Retrieval");
	sections.push(
		'Use `delegation_read("id")` to access full delegation output.',
	);
	sections.push(
		"Do not poll delegation_list for completion; rely on task notifications.",
	);
	sections.push("</delegation-context>");

	return sections.join("\n");
}

// ==========================================
// PLUGIN EXPORT
// ==========================================

/**
 * Expected input for experimental.chat.system.transform hook.
 */
interface SystemTransformInput {
	sessionID?: string;
}

const BackgroundAgentsPlugin: Plugin = async (ctx) => {
	const { client, directory, project } = ctx;

	// Create logger early for all components
	const log = createLogger(client as OpencodeClient);

	// Project-level storage directory (shared across sessions)
	// Uses git root commit hash for cross-worktree consistency
	const projectId = await getProjectId(directory);
	const baseDir = path.join(
		os.homedir(),
		".local",
		"share",
		"opencode",
		"delegations",
		projectId,
	);
	const worktreeDatabase = await initStateDb(directory, project?.id);
	const isNonDefaultWorktree = await isLinkedWorktree(directory, log);
	const isManagedWorktreePath = (candidate: string): boolean => {
		const resolvedCandidate = path.resolve(candidate);
		return getAllSessions(worktreeDatabase).some((session) =>
			isPathWithinRoot(path.resolve(session.path), resolvedCandidate),
		);
	};
	const isManagedNonDefaultWorktreeSession = async (
		sessionID: string | undefined,
	): Promise<boolean> => {
		if (!isNonDefaultWorktree || !sessionID) return false;

		let currentSessionID = sessionID;
		for (let depth = 0; depth < 10; depth++) {
			const session = getSession(worktreeDatabase, currentSessionID);
			if (session && path.resolve(session.path) === path.resolve(directory))
				return true;

			try {
				const response = await client.session.get({
					path: { id: currentSessionID },
				});
				const parentID = response.data?.parentID;
				if (!parentID) return false;
				currentSessionID = parentID;
			} catch (error) {
				log.warn(
					`Managed-worktree ancestry lookup failed for "${currentSessionID}": ${error instanceof Error ? error.message : String(error)}`,
				);
				return false;
			}
		}

		log.warn(
			`Managed-worktree ancestry exceeded maximum depth for "${sessionID}"`,
		);
		return false;
	};

	// Ensure base directory exists (for debug logs etc)
	await fs.mkdir(baseDir, { recursive: true });

	const manager = new DelegationManager(client as OpencodeClient, baseDir, log);

	await manager.debugLog(
		"BackgroundAgentsPlugin initialized with delegation system",
	);

	return {
		tool: {
			delegate: createDelegate(manager),
			delegation_read: createDelegationRead(manager),
			delegation_list: createDelegationList(manager),
		},

		// Prevent read-only agents from using native task tool (symmetric to delegate enforcement)
		"tool.execute.before": async (
			input: { tool: string; sessionID?: string },
			output: {
				args?: {
					subagent_type?: string;
					command?: string;
					filePath?: string;
					path?: string;
					patch?: string;
					patchText?: string;
					patch_text?: string;
					input?: string;
					cwd?: string;
					workdir?: string;
				};
			},
		) => {
			if (PROVIDER_TOOL_ALIASES.has(input.tool)) {
				throw new Error(
					`❌ Provider tool alias '${input.tool}' is disabled. Use the permission-controlled OpenCode tool instead.`,
				);
			}

			if (
				input.tool === "edit" ||
				input.tool === "write" ||
				input.tool === "apply_patch"
			) {
				const callerAgent = await parseSessionAgent(
					client as OpencodeClient,
					input.sessionID ?? "",
					log,
				);
				const allowedAgent = callerAgent === "coder" || callerAgent === "scribe";
				if (!allowedAgent) {
					throw new Error(
						`❌ ${input.tool} is restricted to an authorized write leaf inside a managed worktree.`,
					);
				}
				const targetPaths =
					input.tool === "apply_patch"
						? extractApplyPatchPaths(output.args)
						: [output.args?.filePath ?? output.args?.path ?? ""];
				if (targetPaths.length === 0) {
					throw new Error(
						`❌ Cannot authorize ${input.tool}: no target paths were found.`,
					);
				}
				if (
					callerAgent === "scribe" &&
					targetPaths.some(
						(targetPath) =>
							!SCRIBE_EXTENSIONS.has(path.extname(targetPath).toLowerCase()),
					)
				) {
					throw new Error(
						"❌ Scribe may write only Markdown and text documentation files.",
					);
				}
				if (!(await isManagedNonDefaultWorktreeSession(input.sessionID))) {
					throw new Error(
						`❌ Agent '${callerAgent}' can only use ${input.tool} inside a managed, non-default worktree session.`,
					);
				}

				for (const targetPath of targetPaths) {
					const handoffRoot =
						callerAgent === "scribe"
							? await trustedTemporaryHandoffRoot(targetPath)
							: null;
					const violation = await mutationTargetViolation(
						handoffRoot ?? directory,
						targetPath,
					);
					if (violation) {
						throw new Error(`❌ Cannot authorize ${input.tool}: ${violation}.`);
					}
				}
				return;
			}

			if (input.tool === "bash") {
				const callerAgent = await parseSessionAgent(
					client as OpencodeClient,
					input.sessionID ?? "",
					log,
				);
				if (!callerAgent) {
					throw new Error(
						"❌ Cannot authorize shell execution: caller session identity is unknown.",
					);
				}
				if (callerAgent !== "build" && callerAgent !== "coder") {
					throw new Error(
						`❌ Agent '${callerAgent}' is not allowed to execute shell commands.`,
					);
				}

				const command = output.args?.command ?? "";
				for (const workingDirectory of [
					output.args?.cwd,
					output.args?.workdir,
				]) {
					if (!workingDirectory) continue;
					const violation = await mutationTargetViolation(
						directory,
						workingDirectory,
					);
					const isManagedReadOnlyInspection =
						callerAgent === "build" &&
						!isBuildShellMutation(command) &&
						isManagedWorktreePath(workingDirectory);
					if (violation && !isManagedReadOnlyInspection) {
						throw new Error(
							`❌ Cannot authorize shell working directory: ${violation}.`,
						);
					}
				}

					if (isUnsafeForcePushCommand(command)) {
					throw new Error(
						"❌ Unsafe force-push is forbidden by the orchestration runtime; use --force-with-lease after an explicitly authorized history rewrite.",
					);
					}
					if (callerAgent === "build") {
						const violation = coderStatefulGitInspectionViolation(command);
						if (violation)
							throw new Error(
								`❌ Build shell command rejected: ${violation}.`,
							);
					}
					if (callerAgent === "coder") {
					const violation = coderShellPolicyViolation(command);
					if (violation)
						throw new Error(`❌ Coder shell command rejected: ${violation}.`);
					if (!(await isManagedNonDefaultWorktreeSession(input.sessionID))) {
						throw new Error(
							"❌ Coder shell commands require a managed, non-default worktree session.",
						);
					}
				}
				if (
					callerAgent === "build" &&
					isBuildShellMutation(command) &&
					!(await isManagedNonDefaultWorktreeSession(input.sessionID))
				) {
					throw new Error(
						"❌ Build may mutate Git state or create a PR/MR only from its managed worktree.",
					);
				}
				return;
			}

			// Guard: Only intercept native sub-agent delegation from here on.
			if (input.tool !== "task") return;

			// Guard: Require agent name
			const agentName = output.args?.subagent_type;
			if (!agentName) {
				throw new Error(
					"❌ Cannot authorize native task: target agent is missing.",
				);
			}

			const { isSubAgent } = await parseAgentMode(
				client as OpencodeClient,
				agentName,
				log,
			);
			if (!isSubAgent) {
				throw new Error(
					`❌ Native task may target only an installed sub-agent; '${agentName}' is not one.`,
				);
			}

			// Capability is read from the installed target-agent configuration rather
			// than inferred from its name. This keeps the guard correct as agents change.
			const { isReadOnly: isTargetReadOnly } = await parseAgentWriteCapability(
				client as OpencodeClient,
				agentName,
				log,
			);

			if (!isTargetReadOnly) {
				const parentAgent = await parseSessionAgent(
					client as OpencodeClient,
					input.sessionID ?? "",
					log,
				);
				if (!parentAgent) {
					throw new Error(
						`❌ Cannot authorize delegation to write-capable agent '${agentName}': caller session identity could not be resolved.`,
					);
				}

				if (!WRITE_LEAF_AGENTS.has(agentName)) {
					throw new Error(
						`❌ Write-capable agent '${agentName}' is not an authorized write leaf.`,
					);
				}

				if (isPlanDelegatingToWriteCapable(parentAgent, isTargetReadOnly)) {
					throw new Error(
						`❌ Planning sessions cannot delegate to write-capable agent '${agentName}'. Hand off to a read-only route or the build orchestrator.`,
					);
				}
				if (parentAgent !== "build") {
					throw new Error(
						`❌ Only the build orchestrator may delegate to write-capable agent '${agentName}'.`,
					);
				}

				if (!(await isManagedNonDefaultWorktreeSession(input.sessionID))) {
					throw new Error(
						`❌ Write-capable agent '${agentName}' can only be delegated from a managed, non-default worktree session.`,
					);
				}

				return;
			}

			// Fail fast: Read-only sub-agent via task is invalid
			throw new Error(
				`❌ Agent '${agentName}' is read-only and should use the delegate tool for async background execution.\n\n` +
					`Read-only agents deny all direct and indirect mutation tools without exceptions.\n` +
					`Call delegate with agent: "${agentName}" for this read-only sub-agent.\n` +
					`Use task for write-capable sub-agents.`,
			);
		},

		// Inject delegation rules into system prompt
		"experimental.chat.system.transform": async (
			_input: SystemTransformInput,
			output,
		) => {
			output.system.push(DELEGATION_RULES);
		},

		// Deliver queued parent notifications on the next user turn if direct delivery failed.
		"chat.message": async (
			input: { sessionID?: string },
			output: { parts?: Array<{ type: string; text?: string }> },
		) => {
			if (!input.sessionID) return;
			manager.injectPendingNotificationsIntoChatMessage(
				output,
				input.sessionID,
			);
		},

		// Compaction hook - inject delegation context for context recovery
		"experimental.session.compacting": async (
			input: { sessionID: string },
			output: { context: string[]; prompt?: string },
		) => {
			const rootSessionID = await manager.getRootSessionID(input.sessionID);

			// Running delegations in this root session tree
			const running = manager.getRunningDelegations(rootSessionID).map((d) => ({
				id: d.id,
				agent: d.agent,
				title: d.title,
				description: d.description,
				status: d.status,
				startedAt: d.startedAt,
				lastHeartbeatAt: d.progress.lastHeartbeatAt,
				prompt: d.prompt,
			}));

			// Unread completed delegations to carry forward through compaction
			const unreadCompleted = manager
				.getUnreadCompletedDelegations(rootSessionID, 10)
				.map((d) => ({
					id: d.id,
					agent: d.agent,
					title: d.title,
					description: d.description,
					status: d.status,
					completedAt: d.completedAt,
				}));

			// Early exit if nothing to inject
			if (running.length === 0 && unreadCompleted.length === 0) return;

			output.context.push(formatDelegationContext(running, unreadCompleted));
		},

		// Event hook
		event: async ({ event }: { event: Event }): Promise<void> => {
			if (event.type === "session.status") {
				const statusType = event.properties.status?.type;
				const sessionID = event.properties.sessionID;
				if (statusType === "idle" && sessionID) {
					await manager.handleSessionIdle(sessionID);
				}
			}

			if (event.type === "session.idle") {
				const sessionID = event.properties.sessionID;
				if (sessionID) {
					await manager.handleSessionIdle(sessionID);
				}
			}

			if (event.type === "message.updated") {
				const eventProperties = event.properties as {
					info: { sessionID?: string; role?: string };
					parts?: Part[];
				};
				const sessionID = eventProperties.info.sessionID;
				if (sessionID) {
					const messageText =
						eventProperties.info.role === "assistant"
							? (eventProperties.parts
									?.filter((part) => part.type === "text")
									.map((part) => part.text)
									.join("\n") ?? undefined)
							: undefined;
					manager.handleMessageEvent(sessionID, messageText);
				}
			}
		},
	};
};

const BackgroundAgentsPluginWithInternals = Object.assign(
	BackgroundAgentsPlugin,
	{
		testInternals: {
			DelegationManager,
			coderShellPolicyViolation,
			formatDelegationContext,
			isAgentPermissionReadOnly,
			isBuildShellMutation,
			isForcePushCommand,
			isLeaseProtectedForcePushCommand,
			isPermissionCompletelyDenied,
			isPlanDelegatingToWriteCapable,
			isUnsafeForcePushCommand,
			permissionKeyMatchesTool,
			resolveToolPermission,
		},
	} as const,
);

export default BackgroundAgentsPluginWithInternals;
