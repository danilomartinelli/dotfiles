import { randomUUID } from "node:crypto";
import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import { type Plugin, tool } from "@opencode-ai/plugin";
import { z } from "zod";
import { getProjectId } from "../kdco-primitives/get-project-id";
import { assertSafeStorageSegment } from "../kdco-primitives/storage-id";

const PhaseStatus = z.enum(["PENDING", "IN PROGRESS", "COMPLETE", "BLOCKED"]);
const Citation = z
	.string()
	.regex(/^ref:[a-z]+-[a-z]+-[a-z]+$/, "Invalid delegation citation");

const TaskSchema = z
	.object({
		id: z
			.string()
			.regex(/^\d+\.\d+$/, "Task ID must be hierarchical (for example, 2.1)"),
		checked: z.boolean(),
		content: z.string().min(1, "Task content cannot be empty"),
		isCurrent: z.boolean(),
		citation: Citation.optional(),
	})
	.strict();

const PhaseSchema = z
	.object({
		number: z.number().int().positive(),
		name: z.string().min(1, "Phase name cannot be empty"),
		status: PhaseStatus,
		tasks: z.array(TaskSchema).min(1, "Phase must have at least one task"),
	})
	.strict();

const ContextDecisionSchema = z
	.object({
		decision: z.string().min(1, "Decision cannot be empty"),
		rationale: z.string().min(1, "Rationale cannot be empty"),
		source: Citation,
	})
	.strict();

function isValidCalendarDate(value: string): boolean {
	const parsed = new Date(`${value}T00:00:00.000Z`);
	return (
		!Number.isNaN(parsed.getTime()) &&
		parsed.toISOString().slice(0, 10) === value
	);
}

const FrontmatterSchema = z
	.object({
		status: z.enum(["not-started", "in-progress", "complete", "blocked"]),
		phase: z.number().int().positive(),
		updated: z
			.string()
			.regex(/^\d{4}-\d{2}-\d{2}$/, "Date must be YYYY-MM-DD")
			.refine(isValidCalendarDate, "Date must be a real calendar date"),
	})
	.strict();

const PlanSchema = z
	.object({
		frontmatter: FrontmatterSchema,
		goal: z.string().min(10, "Goal must be at least 10 characters"),
		context: z.array(ContextDecisionSchema),
		phases: z.array(PhaseSchema).min(1, "Plan must have at least one phase"),
		notes: z.string().min(1, "Notes section must contain at least one entry"),
	})
	.strict();

type ParsedPlan = z.infer<typeof PlanSchema>;
type ParseResult =
	| { ok: true; data: ParsedPlan; citations: string[] }
	| { ok: false; error: string; hint: string };

interface ExtractedParts {
	frontmatter: Record<string, string | number> | null;
	goal: string | null;
	context: Array<{ decision: string; rationale: string; source: string }>;
	phases: Array<{
		number: number;
		name: string;
		status: string;
		tasks: Array<{
			id: string;
			checked: boolean;
			content: string;
			isCurrent: boolean;
			citation?: string;
		}>;
	}>;
	notes: string | null;
	syntaxErrors: string[];
}

function extractSection(content: string, heading: string): string | null {
	const escapedHeading = heading.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
	const match = content.match(
		new RegExp(
			`^## ${escapedHeading}\\s*$\\n([\\s\\S]*?)(?=^## \\S|$(?![\\s\\S]))`,
			"m",
		),
	);
	return match?.[1]?.trim() ?? null;
}

function parseFrontmatter(
	content: string,
	syntaxErrors: string[],
): Record<string, string | number> | null {
	const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
	if (!match) return null;
	const frontmatter: Record<string, string | number> = {};
	for (const [index, line] of match[1].split(/\r?\n/).entries()) {
		if (!line.trim()) continue;
		const separator = line.indexOf(":");
		if (separator < 1) {
			syntaxErrors.push(`Malformed frontmatter at line ${index + 2}`);
			continue;
		}
		const key = line.slice(0, separator).trim();
		const value = line.slice(separator + 1).trim();
		if (Object.hasOwn(frontmatter, key)) {
			syntaxErrors.push(`Duplicate frontmatter field: ${key}`);
			continue;
		}
		frontmatter[key] =
			key === "phase" && /^\d+$/.test(value) ? Number(value) : value;
	}
	return frontmatter;
}

function parseContextTable(
	section: string | null,
	syntaxErrors: string[],
): ExtractedParts["context"] {
	if (section === null) {
		syntaxErrors.push("Missing required ## Context & Decisions section");
		return [];
	}

	const lines = section
		.split(/\r?\n/)
		.map((line) => line.trim())
		.filter(Boolean);
	for (const [index, line] of lines.entries()) {
		if (!line.startsWith("|") || !line.endsWith("|")) {
			syntaxErrors.push(
				`Unexpected non-table content in Context & Decisions at row ${index + 1}`,
			);
		}
	}
	const rows = lines
		.filter((line) => line.startsWith("|") && line.endsWith("|"))
		.map((line) =>
			line
				.slice(1, -1)
				.split("|")
				.map((cell) => cell.trim()),
		);
	if (rows.length < 2) {
		syntaxErrors.push(
			"Context & Decisions must contain the three-column table header",
		);
		return [];
	}

	const header = rows[0].map((cell) => cell.toLowerCase());
	if (header.join("|") !== "decision|rationale|source") {
		syntaxErrors.push(
			"Context & Decisions columns must be Decision | Rationale | Source",
		);
	}
	if (
		rows[1].length !== 3 ||
		!rows[1].every((cell) => /^:?-{3,}:?$/.test(cell))
	) {
		syntaxErrors.push(
			"Context & Decisions must use a valid three-column separator row",
		);
	}

	return rows.slice(2).flatMap((cells, index) => {
		if (cells.length !== 3) {
			syntaxErrors.push(
				`Context decision row ${index + 1} must contain exactly three cells`,
			);
			return [];
		}
		return [
			{
				decision: cells[0],
				rationale: cells[1],
				source: cells[2].replaceAll("`", ""),
			},
		];
	});
}

function parseTaskLine(
	line: string,
	phaseNumber: number,
	lineNumber: number,
	syntaxErrors: string[],
): ExtractedParts["phases"][number]["tasks"][number] | null {
	const checkbox = line.match(/^- \[([ xX])\] (.+)$/);
	if (!checkbox) {
		if (line.trim()) syntaxErrors.push(`Malformed task at line ${lineNumber}`);
		return null;
	}

	const rawBody = checkbox[2];
	const citations = [
		...rawBody.matchAll(/`?(ref:[a-z]+-[a-z]+-[a-z]+)`?/g),
	].map((match) => match[1]);
	if (citations.length > 1)
		syntaxErrors.push(`Task at line ${lineNumber} has multiple citations`);

	const isCurrent = rawBody.includes("← CURRENT");
	const normalizedBody = rawBody
		.replace(/\s*← CURRENT\s*/g, " ")
		.replace(/\s*(?:→\s*)?`?ref:[a-z]+-[a-z]+-[a-z]+`?/g, " ")
		.replaceAll("**", "")
		.trim();
	const taskMatch = normalizedBody.match(/^(\d+\.\d+)\s+(.+)$/);
	if (!taskMatch) {
		syntaxErrors.push(
			`Task at line ${lineNumber} must start with a hierarchical ID`,
		);
		return null;
	}
	if (!taskMatch[1].startsWith(`${phaseNumber}.`)) {
		syntaxErrors.push(
			`Task ${taskMatch[1]} must belong to Phase ${phaseNumber}`,
		);
	}

	return {
		id: taskMatch[1],
		checked: checkbox[1].toLowerCase() === "x",
		content: taskMatch[2].trim(),
		isCurrent,
		citation: citations[0],
	};
}

function parsePhases(
	content: string,
	syntaxErrors: string[],
): ExtractedParts["phases"] {
	const phaseHeader =
		/^## Phase (\d+): (.+?) \[(PENDING|IN PROGRESS|COMPLETE|BLOCKED)\]\s*$/gm;
	for (const [lineIndex, line] of content.split(/\r?\n/).entries()) {
		if (
			/^## Phase\b/.test(line) &&
			!new RegExp(phaseHeader.source).test(line)
		) {
			syntaxErrors.push(`Malformed phase heading at line ${lineIndex + 1}`);
		}
	}
	const headers = [...content.matchAll(phaseHeader)];
	return headers.map((header, index) => {
		const number = Number.parseInt(header[1], 10);
		const bodyStart = (header.index ?? 0) + header[0].length;
		const nextHeader = headers[index + 1]?.index ?? content.length;
		const trailingSection = content
			.slice(bodyStart, nextHeader)
			.search(/^## \S.*$/m);
		const bodyEnd =
			trailingSection >= 0 ? bodyStart + trailingSection : nextHeader;
		const body = content.slice(bodyStart, bodyEnd);
		const bodyStartLine = content.slice(0, bodyStart).split(/\r?\n/).length;
		const tasks = body
			.split(/\r?\n/)
			.map((line, lineOffset) =>
				parseTaskLine(line, number, bodyStartLine + lineOffset, syntaxErrors),
			)
			.filter((task): task is NonNullable<typeof task> => task !== null);

		return {
			number,
			name: header[2].trim(),
			status: header[3],
			tasks,
		};
	});
}

function extractMarkdownParts(content: string): ExtractedParts {
	const syntaxErrors: string[] = [];
	const titleCount = [...content.matchAll(/^# Implementation Plan\s*$/gm)]
		.length;
	if (titleCount !== 1) {
		syntaxErrors.push(
			"Plan must contain exactly one # Implementation Plan heading",
		);
	}
	for (const heading of ["Goal", "Context & Decisions", "Notes"]) {
		const escaped = heading.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
		const count = [...content.matchAll(new RegExp(`^## ${escaped}\\s*$`, "gm"))]
			.length;
		if (count !== 1)
			syntaxErrors.push(`Plan must contain exactly one ## ${heading} section`);
	}
	const goalSection = extractSection(content, "Goal");
	const goal =
		goalSection
			?.split(/\r?\n/)
			.find((line) => line.trim())
			?.trim() ?? null;
	const context = parseContextTable(
		extractSection(content, "Context & Decisions"),
		syntaxErrors,
	);
	const phases = parsePhases(content, syntaxErrors);
	const notes = extractSection(content, "Notes");
	return {
		frontmatter: parseFrontmatter(content, syntaxErrors),
		goal,
		context,
		phases,
		notes,
		syntaxErrors,
	};
}

function formatZodErrors(error: z.ZodError): string {
	return error.issues
		.map(
			(issue) =>
				`${issue.path.length ? `[${issue.path.join(".")}]` : "[root]"}: ${issue.message}`,
		)
		.join("\n");
}

function validatePlanState(plan: ParsedPlan): string[] {
	const errors: string[] = [];
	const phaseNumbers = plan.phases.map((phase) => phase.number);
	if (new Set(phaseNumbers).size !== phaseNumbers.length)
		errors.push("Phase numbers must be unique");
	for (const [index, phaseNumber] of phaseNumbers.entries()) {
		if (phaseNumber !== index + 1) {
			errors.push("Phase numbers must be contiguous and ordered from 1");
			break;
		}
	}
	if (!phaseNumbers.includes(plan.frontmatter.phase)) {
		errors.push(`Frontmatter phase ${plan.frontmatter.phase} does not exist`);
	}

	const taskIds = plan.phases.flatMap((phase) =>
		phase.tasks.map((task) => task.id),
	);
	if (new Set(taskIds).size !== taskIds.length)
		errors.push("Task IDs must be unique");

	const currentTasks = plan.phases.flatMap((phase) =>
		phase.tasks
			.filter((task) => task.isCurrent)
			.map((task) => ({ phase, task })),
	);
	const inProgressPhases = plan.phases.filter(
		(phase) => phase.status === "IN PROGRESS",
	);
	const blockedPhases = plan.phases.filter(
		(phase) => phase.status === "BLOCKED",
	);

	for (const phase of plan.phases) {
		let foundUncheckedTask = false;
		for (const task of phase.tasks) {
			if (!task.checked) foundUncheckedTask = true;
			else if (foundUncheckedTask) {
				errors.push(
					`Phase ${phase.number} has a completed task after an incomplete task`,
				);
				break;
			}
		}
		if (
			phase.status === "COMPLETE" &&
			phase.tasks.some((task) => !task.checked)
		) {
			errors.push(`Phase ${phase.number} is COMPLETE but has unchecked tasks`);
		}
		if (
			phase.status === "PENDING" &&
			phase.tasks.some((task) => task.checked || task.isCurrent)
		) {
			errors.push(
				`Phase ${phase.number} is PENDING but contains started tasks`,
			);
		}
	}

	if (plan.frontmatter.status === "in-progress") {
		if (inProgressPhases.length !== 1)
			errors.push("An in-progress plan requires exactly one IN PROGRESS phase");
		if (currentTasks.length !== 1)
			errors.push("An in-progress plan requires exactly one CURRENT task");
		const activePhase = inProgressPhases[0];
		const current = currentTasks[0];
		if (activePhase && activePhase.number !== plan.frontmatter.phase) {
			errors.push("Frontmatter phase must match the IN PROGRESS phase");
		}
		if (activePhase && current && activePhase.number !== current.phase.number) {
			errors.push("CURRENT task must belong to the IN PROGRESS phase");
		}
		if (current?.task.checked) errors.push("CURRENT task must be unchecked");
	}

	if (plan.frontmatter.status === "not-started") {
		if (currentTasks.length !== 0 || inProgressPhases.length !== 0) {
			errors.push(
				"A not-started plan cannot have a CURRENT task or IN PROGRESS phase",
			);
		}
		if (plan.phases.some((phase) => phase.status !== "PENDING")) {
			errors.push("Every phase in a not-started plan must be PENDING");
		}
	}

	if (plan.frontmatter.status === "complete") {
		if (currentTasks.length !== 0 || inProgressPhases.length !== 0) {
			errors.push(
				"A complete plan cannot have a CURRENT task or IN PROGRESS phase",
			);
		}
		if (plan.phases.some((phase) => phase.status !== "COMPLETE")) {
			errors.push("Every phase in a complete plan must be COMPLETE");
		}
	}

	if (plan.frontmatter.status === "blocked") {
		if (blockedPhases.length !== 1)
			errors.push("A blocked plan requires exactly one BLOCKED phase");
		if (inProgressPhases.length !== 0)
			errors.push("A blocked plan cannot also have an IN PROGRESS phase");
		if (currentTasks.length > 1)
			errors.push("A blocked plan may retain at most one CURRENT task");
		if (currentTasks[0]?.task.checked)
			errors.push(
				"A retained CURRENT task in a blocked plan must be unchecked",
			);
		if (
			blockedPhases[0] &&
			currentTasks[0] &&
			blockedPhases[0].number !== currentTasks[0].phase.number
		) {
			errors.push("A retained CURRENT task must belong to the BLOCKED phase");
		}
		if (
			blockedPhases[0] &&
			blockedPhases[0].number !== plan.frontmatter.phase
		) {
			errors.push("Frontmatter phase must match the BLOCKED phase");
		}
	}

	return errors;
}

function parsePlanMarkdown(content: string): ParseResult {
	const hint =
		"Load skill('plan-protocol') for the complete format and lifecycle rules.";
	if (typeof content !== "string" || !content.trim()) {
		return {
			ok: false,
			error: "Plan content must be a non-empty markdown string",
			hint,
		};
	}

	const parts = extractMarkdownParts(content);
	if (parts.syntaxErrors.length) {
		return { ok: false, error: parts.syntaxErrors.join("\n"), hint };
	}

	const parsed = PlanSchema.safeParse({
		frontmatter: parts.frontmatter,
		goal: parts.goal,
		context: parts.context,
		phases: parts.phases,
		notes: parts.notes,
	});
	if (!parsed.success)
		return { ok: false, error: formatZodErrors(parsed.error), hint };

	const stateErrors = validatePlanState(parsed.data);
	if (stateErrors.length)
		return { ok: false, error: stateErrors.join("\n"), hint };

	const citations = [
		...content.matchAll(/`?(ref:[a-z]+-[a-z]+-[a-z]+)`?/g),
	].map((match) => match[1]);
	return { ok: true, data: parsed.data, citations: [...new Set(citations)] };
}

function formatParseError(error: string, hint: string): string {
	return `Plan validation failed:\n\n${error}\n\n${hint}`;
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
	return error instanceof Error && "code" in error;
}

async function findMissingCitations(
	delegationsDirectory: string,
	citations: string[],
): Promise<string[]> {
	const missing: string[] = [];
	for (const citation of citations) {
		const delegationId = citation.slice("ref:".length);
		try {
			const stats = await fs.lstat(
				path.join(delegationsDirectory, `${delegationId}.md`),
			);
			if (!stats.isFile() || stats.size === 0) missing.push(citation);
		} catch (error) {
			if (isNodeError(error) && error.code === "ENOENT") missing.push(citation);
			else throw error;
		}
	}
	return missing;
}

interface SystemTransformInput {
	sessionID?: string;
	model?: unknown;
}

interface ActiveCoderCall {
	rootSessionID: string;
	startTime: number;
}

const STALE_CALL_TIMEOUT_MS = 15 * 60 * 1000;

function pruneStaleCoderCalls(
	activeCalls: Map<string, ActiveCoderCall>,
	now = Date.now(),
): void {
	for (const [callID, data] of activeCalls) {
		if (now - data.startTime > STALE_CALL_TIMEOUT_MS)
			activeCalls.delete(callID);
	}
}

function hasActiveCoderCallForRoot(
	activeCalls: Map<string, ActiveCoderCall>,
	rootSessionID: string,
): boolean {
	return [...activeCalls.values()].some(
		(call) => call.rootSessionID === rootSessionID,
	);
}

const WorkspacePlugin: Plugin = async (ctx) => {
	const { directory } = ctx;
	const projectId = await getProjectId(directory);
	const baseDir = path.join(
		os.homedir(),
		".local",
		"share",
		"opencode",
		"workspace",
		projectId,
	);
	const delegationsBaseDir = path.join(
		os.homedir(),
		".local",
		"share",
		"opencode",
		"delegations",
		projectId,
	);
	const activeCoderCalls = new Map<string, ActiveCoderCall>();

	async function getRootSessionID(sessionID?: string): Promise<string> {
		if (!sessionID)
			throw new Error("sessionID is required to resolve root session scope");
		let currentID = assertSafeStorageSegment(sessionID, "Session ID");
		const visited = new Set<string>();
		for (let depth = 0; depth < 10; depth++) {
			if (visited.has(currentID))
				throw new Error(
					"Failed to resolve root session: parent cycle detected",
				);
			visited.add(currentID);
			const session = await ctx.client.session.get({ path: { id: currentID } });
			if (!session.data?.parentID) return currentID;
			currentID = assertSafeStorageSegment(
				session.data.parentID,
				"Parent session ID",
			);
		}
		throw new Error(
			"Failed to resolve root session: maximum traversal depth exceeded",
		);
	}

	return {
		tool: {
			plan_save: tool({
				description:
					"Validate and atomically save the implementation plan. Every cited delegation must exist in this root session.",
				args: {
					content: tool.schema
						.string()
						.describe("The full plan in markdown format"),
				},
				async execute(args, toolCtx) {
					if (!toolCtx?.sessionID)
						return "Plan save failed: sessionID is required.";
					const result = parsePlanMarkdown(args.content);
					if (!result.ok) return formatParseError(result.error, result.hint);

					const rootID = await getRootSessionID(toolCtx.sessionID);
					const missingCitations = await findMissingCitations(
						path.join(delegationsBaseDir, rootID),
						result.citations,
					);
					if (missingCitations.length) {
						return formatParseError(
							`Citations do not resolve to persisted delegation artifacts: ${missingCitations.join(", ")}`,
							"Use delegation_read before citing a delegation and save again.",
						);
					}

					const sessionDir = path.join(baseDir, rootID);
					await fs.mkdir(sessionDir, { recursive: true });
					const planPath = path.join(sessionDir, "plan.md");
					const temporaryPath = path.join(
						sessionDir,
						`.plan.${randomUUID()}.tmp`,
					);
					try {
						await fs.writeFile(temporaryPath, args.content, {
							encoding: "utf8",
							mode: 0o600,
						});
						await fs.rename(temporaryPath, planPath);
					} finally {
						await fs.rm(temporaryPath, { force: true }).catch(() => undefined);
					}
					return "Plan saved.";
				},
			}),

			plan_read: tool({
				description:
					"Read the current implementation plan for this root session.",
				args: {
					reason: tool.schema
						.string()
						.describe("Brief explanation of why the plan is needed"),
				},
				async execute(_args, toolCtx) {
					if (!toolCtx?.sessionID)
						return "Plan read failed: sessionID is required.";
					const rootID = await getRootSessionID(toolCtx.sessionID);
					try {
						return await fs.readFile(
							path.join(baseDir, rootID, "plan.md"),
							"utf8",
						);
					} catch (error) {
						if (isNodeError(error) && error.code === "ENOENT")
							return "No plan found.";
						throw error;
					}
				},
			}),
		},

		"experimental.chat.system.transform": async (
			_input: SystemTransformInput,
			output,
		) => {
			const now = new Date();
			output.system.push(`<date-awareness>
Today is ${now.toISOString().split("T")[0]}. When searching for documentation, APIs, or external resources, use the current year (${now.getFullYear()}). Do not default to outdated years from training data.
</date-awareness>`);
		},

		"tool.execute.before": async (
			input: { tool: string; callID?: string; sessionID?: string },
			output: { args?: { subagent_type?: string } },
		) => {
			if (input.tool !== "task" || !input.callID || !input.sessionID) return;
			if (output.args?.subagent_type !== "coder") return;
			pruneStaleCoderCalls(activeCoderCalls);
			activeCoderCalls.set(input.callID, {
				rootSessionID: await getRootSessionID(input.sessionID),
				startTime: Date.now(),
			});
		},

		"tool.execute.after": async (
			input: { tool: string; sessionID: string; callID: string },
			output: { title: string; output: string; metadata: unknown },
		) => {
			if (input.tool === "plan_save") {
				if (!output.output.startsWith("Plan saved.")) return;
				output.output += `\n\n<system-reminder>
Plan saved successfully. Delegate it to reviewer with delegate, then use plan_read to supply the exact saved content. The review is non-blocking.
</system-reminder>`;
				return;
			}

			if (!input.callID) return;
			const completedCall = activeCoderCalls.get(input.callID);
			if (!completedCall) return;
			activeCoderCalls.delete(input.callID);
			pruneStaleCoderCalls(activeCoderCalls);
			if (
				hasActiveCoderCallForRoot(activeCoderCalls, completedCall.rootSessionID)
			)
				return;

			output.output += `\n\n<system-reminder>
All coder tasks for this root session are complete. Delegate reviewer with the changed files and explicit diff context before reporting completion.
</system-reminder>`;
		},

		"experimental.session.compacting": async (
			input: { sessionID: string },
			output: { context: string[]; prompt?: string },
		) => {
			const rootID = await getRootSessionID(input.sessionID);
			let planContent: string | null = null;
			try {
				planContent = await fs.readFile(
					path.join(baseDir, rootID, "plan.md"),
					"utf8",
				);
			} catch (error) {
				if (!isNodeError(error) || error.code !== "ENOENT") throw error;
			}
			if (!planContent) return;

			const currentTask = planContent
				.split(/\r?\n/)
				.find((line) => line.includes("← CURRENT"))
				?.replace(/^\s*- \[[ xX]\]\s*/, "")
				.replace(/\s*← CURRENT.*$/, "")
				.replaceAll("**", "")
				.trim();
			output.context.push(`<workspace-context>
## Current Plan
${planContent}

## Resume Point
${currentTask ? `Current task: ${currentTask}` : "No active task; follow the plan lifecycle state."}

## Verification
Resolve every cited decision with delegation_read before relying on it.
</workspace-context>`);
		},
	};
};

const WorkspacePluginWithInternals = Object.assign(WorkspacePlugin, {
	testInternals: {
		extractMarkdownParts,
		findMissingCitations,
		hasActiveCoderCallForRoot,
		parsePlanMarkdown,
		pruneStaleCoderCalls,
		validatePlanState,
	},
} as const);

export default WorkspacePluginWithInternals;
