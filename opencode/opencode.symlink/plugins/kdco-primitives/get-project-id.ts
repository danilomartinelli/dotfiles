/**
 * Clone-safe project identity shared by all linked worktrees of one checkout.
 */

import * as crypto from "node:crypto";
import { realpath } from "node:fs/promises";
import * as path from "node:path";
import { logWarn } from "./log-warn";
import type { OpencodeClient } from "./types";
import { TimeoutError, withTimeout } from "./with-timeout";

function hashIdentity(identity: string): string {
	return crypto
		.createHash("sha256")
		.update(identity)
		.digest("hex")
		.slice(0, 32);
}

async function canonicalPath(candidate: string): Promise<string> {
	return realpath(candidate).catch(() => path.resolve(candidate));
}

interface GitIdentity {
	commonDirectory: string;
	rootCommits: string[];
}

async function readGitIdentity(
	projectRoot: string,
	client?: OpencodeClient,
): Promise<GitIdentity | null> {
	const process = Bun.spawn(
		["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
		{
			cwd: projectRoot,
			stdout: "pipe",
			stderr: "pipe",
			env: {
				...globalThis.process.env,
				GIT_DIR: undefined,
				GIT_WORK_TREE: undefined,
			},
		},
	);

	const timeoutMs = 5000;
	const exitCode = await withTimeout(
		process.exited,
		timeoutMs,
		"git rev-parse timed out",
	).catch((error) => {
		if (error instanceof TimeoutError) process.kill();
		return 1;
	});
	if (exitCode !== 0) return null;

	const commonDirectoryOutput = (
		await new Response(process.stdout).text()
	).trim();
	if (!commonDirectoryOutput) return null;
	const commonDirectory = await canonicalPath(commonDirectoryOutput);

	const rootsProcess = Bun.spawn(
		["git", "rev-list", "--max-parents=0", "--all"],
		{
			cwd: projectRoot,
			stdout: "pipe",
			stderr: "pipe",
			env: {
				...globalThis.process.env,
				GIT_DIR: undefined,
				GIT_WORK_TREE: undefined,
			},
		},
	);
	const rootsExitCode = await withTimeout(
		rootsProcess.exited,
		timeoutMs,
		"git rev-list timed out",
	).catch((error) => {
		if (error instanceof TimeoutError) rootsProcess.kill();
		return 1;
	});
	if (rootsExitCode !== 0) {
		const stderr = (await new Response(rootsProcess.stderr).text()).trim();
		logWarn(
			client,
			"project-id",
			`git rev-list failed (${rootsExitCode}): ${stderr}`,
		);
		return { commonDirectory, rootCommits: [] };
	}

	const rootCommits = (await new Response(rootsProcess.stdout).text())
		.split("\n")
		.map((value) => value.trim())
		.filter((value) => /^[a-f0-9]{40}$/i.test(value))
		.sort();
	return { commonDirectory, rootCommits };
}

/**
 * Generate an ID that is identical for linked worktrees but distinct for
 * independent clones, even when their Git history is identical.
 */
export async function getProjectId(
	projectRoot: string,
	client?: OpencodeClient,
): Promise<string> {
	if (!projectRoot || typeof projectRoot !== "string") {
		throw new Error(
			"getProjectId: projectRoot is required and must be a string",
		);
	}

	const canonicalRoot = await canonicalPath(projectRoot);
	try {
		const gitIdentity = await readGitIdentity(canonicalRoot, client);
		if (gitIdentity) {
			return hashIdentity(
				[
					"git-v2",
					gitIdentity.commonDirectory,
					...gitIdentity.rootCommits,
				].join("\0"),
			);
		}
	} catch (error) {
		logWarn(client, "project-id", `Git identity lookup failed: ${error}`);
	}

	logWarn(
		client,
		"project-id",
		`No Git identity found at ${canonicalRoot}; using canonical path`,
	);
	return hashIdentity(["path-v2", canonicalRoot].join("\0"));
}

export const projectIdTestInternals = {
	canonicalPath,
	hashIdentity,
	readGitIdentity,
} as const;
