import * as path from "node:path";
import type { Plugin } from "@opencode-ai/plugin";
import {
	assertControlledDiscoveryEnvironment,
	isPathWithinRoot,
	loadProjectInstructions,
} from "./internal/project-instructions";

async function resolveGitRoot(directory: string): Promise<string> {
	const child = Bun.spawn(["git", "rev-parse", "--show-toplevel"], {
		cwd: directory,
		stdout: "pipe",
		stderr: "pipe",
	});
	const [stdout, exitCode] = await Promise.all([
		new Response(child.stdout).text(),
		child.exited,
	]);
	if (exitCode !== 0) return path.resolve(directory);

	const root = path.resolve(stdout.trim());
	const current = path.resolve(directory);
	return isPathWithinRoot(root, current) ? root : current;
}

const ProjectInstructionsPlugin: Plugin = async ({ directory }) => {
	assertControlledDiscoveryEnvironment();
	const root = await resolveGitRoot(directory);
	const instructions = await loadProjectInstructions(root, directory);

	return {
		"experimental.chat.system.transform": async (_input, output) => {
			for (const instruction of instructions) {
				output.system.push(
					`Instructions from: ${instruction.path}\n${instruction.content}`,
				);
			}
		},
	};
};

export default ProjectInstructionsPlugin;
