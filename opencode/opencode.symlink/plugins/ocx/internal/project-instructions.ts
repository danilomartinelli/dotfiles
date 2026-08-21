import * as fs from "node:fs/promises";
import * as path from "node:path";

const MAX_INSTRUCTION_BYTES = 256 * 1024;
const REQUIRED_DISABLED_DISCOVERY_FLAGS = [
	"OPENCODE_DISABLE_PROJECT_CONFIG",
	"OPENCODE_DISABLE_EXTERNAL_SKILLS",
	"OPENCODE_DISABLE_CLAUDE_CODE_SKILLS",
] as const;

function isTruthyEnvironmentValue(value: string | undefined): boolean {
	return value === "1" || value?.toLowerCase() === "true";
}

export function assertControlledDiscoveryEnvironment(
	environment: NodeJS.ProcessEnv = process.env,
): void {
	const missing = REQUIRED_DISABLED_DISCOVERY_FLAGS.filter(
		(name) => !isTruthyEnvironmentValue(environment[name]),
	);
	if (missing.length > 0) {
		throw new Error(
			`Controlled OpenCode discovery is not active; missing: ${missing.join(", ")}`,
		);
	}
}

export function isPathWithinRoot(root: string, candidate: string): boolean {
	const relative = path.relative(root, candidate);
	return (
		relative === "" ||
		(!!relative && !relative.startsWith("..") && !path.isAbsolute(relative))
	);
}

export interface ProjectInstruction {
	path: string;
	content: string;
}

export async function loadProjectInstructions(
	root: string,
	directory: string,
): Promise<ProjectInstruction[]> {
	const resolvedRoot = path.resolve(root);
	const resolvedDirectory = path.resolve(directory);
	if (!isPathWithinRoot(resolvedRoot, resolvedDirectory)) {
		throw new Error(
			"Project instruction directory is outside the project root",
		);
	}

	const relative = path.relative(resolvedRoot, resolvedDirectory);
	const directories = [resolvedRoot];
	let cursor = resolvedRoot;
	for (const segment of relative.split(path.sep).filter(Boolean)) {
		cursor = path.join(cursor, segment);
		directories.push(cursor);
	}

	const instructions: ProjectInstruction[] = [];
	for (const candidateDirectory of directories) {
		const candidate = path.join(candidateDirectory, "AGENTS.md");
		const info = await fs.lstat(candidate).catch((error: unknown) => {
			if (
				error instanceof Error &&
				"code" in error &&
				(error as NodeJS.ErrnoException).code === "ENOENT"
			)
				return null;
			throw error;
		});
		if (!info) continue;
		if (!info.isFile() || info.isSymbolicLink()) {
			throw new Error(
				`Project instruction must be a regular file: ${candidate}`,
			);
		}
		if (info.size > MAX_INSTRUCTION_BYTES) {
			throw new Error(
				`Project instruction exceeds ${MAX_INSTRUCTION_BYTES} bytes: ${candidate}`,
			);
		}
		const content = await fs.readFile(candidate, "utf8");
		if (content.trim()) instructions.push({ path: candidate, content });
	}
	return instructions;
}
