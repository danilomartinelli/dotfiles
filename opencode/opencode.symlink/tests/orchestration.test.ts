import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { randomUUID } from "node:crypto";
import { lstat, mkdir, mkdtemp, readdir, rm, symlink } from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import { parse as parseJsonc } from "jsonc-parser";
import { getProjectId } from "../plugins/kdco-primitives/get-project-id";
import { assertSafeStorageSegment } from "../plugins/kdco-primitives/storage-id";
import type { OpencodeClient } from "../plugins/kdco-primitives/types";
import { sendLinuxNotifySendNotification } from "../plugins/notify/backend";
import backgroundAgentsPlugin from "../plugins/ocx/background-agents";
import { assertNoProjectDcpOverride } from "../plugins/ocx/internal/dcp-policy";
import {
	assertControlledDiscoveryEnvironment,
	loadProjectInstructions,
} from "../plugins/ocx/internal/project-instructions";
import runtimeGuardPlugin from "../plugins/ocx/runtime-guard";
import workspacePlugin from "../plugins/ocx/workspace-plugin";
import worktreePlugin from "../plugins/ocx/worktree";
import {
	claimSession,
	clearPendingDelete,
	getAllSessions,
	getAllPendingDeletes,
	getPendingContinuation,
	getPendingDelete,
	getSession,
	getWorktreePath,
	initStateDb,
	setPendingContinuation,
	setPendingDelete,
} from "../plugins/worktree/state";

const configPath = new URL("../opencode.jsonc", import.meta.url);

interface PermissionConfig {
	[key: string]: unknown;
}

interface AgentConfig {
	disable?: boolean;
	prompt?: string;
	permission?: PermissionConfig;
}

interface OpenCodeConfig {
	autoupdate?: boolean | "notify";
	permission?: PermissionConfig;
	agent?: Record<string, AgentConfig>;
	plugin?: string[];
	disabled_providers?: string[];
	provider?: Record<string, unknown>;
}

async function readConfig(): Promise<OpenCodeConfig> {
	return parseJsonc(await Bun.file(configPath).text()) as OpenCodeConfig;
}

function createStateDatabase(): Database {
	const database = new Database(":memory:");
	database.exec("PRAGMA foreign_keys=ON");
	database.exec(`
		CREATE TABLE sessions (
			id TEXT PRIMARY KEY,
			branch TEXT NOT NULL UNIQUE,
			path TEXT NOT NULL UNIQUE,
			created_at TEXT NOT NULL,
			workspace_id TEXT UNIQUE
		);
		CREATE TABLE pending_continuations (
			session_id TEXT PRIMARY KEY,
			workspace_id TEXT NOT NULL UNIQUE,
			created_at TEXT NOT NULL,
			state TEXT NOT NULL DEFAULT 'pending',
			claim_token TEXT,
			claimed_at TEXT,
			FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
		);
		CREATE TABLE pending_deletes (
			session_id TEXT PRIMARY KEY,
			branch TEXT NOT NULL UNIQUE,
			path TEXT NOT NULL UNIQUE,
			created_at TEXT NOT NULL,
			FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
		);
	`);
	return database;
}

function createMinimalClient(): OpencodeClient {
	return {
		app: { log: async () => undefined },
	} as unknown as OpencodeClient;
}

function createAgentClient(
	config: OpenCodeConfig,
	parentAgent: string,
	options: { parentID?: string | null } = {},
): OpencodeClient {
	return {
		app: {
			log: async () => undefined,
			agents: async () => ({
				data: Object.keys(config.agent ?? {}).map((name) => ({
					name,
					mode: "subagent",
				})),
			}),
		},
		config: { get: async () => ({ data: config }) },
		session: {
			messages: async () => ({
				data: [{ info: { role: "user", agent: parentAgent } }],
			}),
			get: async () => ({ data: { parentID: options.parentID ?? null } }),
		},
	} as unknown as OpencodeClient;
}

async function runCommand(command: string[], cwd: string): Promise<void> {
	const process = Bun.spawn(command, { cwd, stdout: "pipe", stderr: "pipe" });
	const [stdout, stderr, exitCode] = await Promise.all([
		new Response(process.stdout).text(),
		new Response(process.stderr).text(),
		process.exited,
	]);
	if (exitCode !== 0)
		throw new Error(`${command.join(" ")} failed: ${stderr || stdout}`);
}

async function createGitRepository(
	prefix: string,
): Promise<{ repository: string; worktree: string }> {
	const repository = await mkdtemp(
		path.join(os.tmpdir(), `${prefix}-repository-`),
	);
	const worktree = `${repository}-worktree`;
	await runCommand(["git", "init", "-q"], repository);
	await runCommand(
		["git", "config", "user.email", "tests@example.invalid"],
		repository,
	);
	await runCommand(
		["git", "config", "user.name", "OpenCode tests"],
		repository,
	);
	await Bun.write(path.join(repository, "README.md"), "test\n");
	await runCommand(["git", "add", "README.md"], repository);
	await runCommand(["git", "commit", "-qm", "initial"], repository);
	await runCommand(
		["git", "worktree", "add", "-qb", "feature/test", worktree, "HEAD"],
		repository,
	);
	return { repository, worktree };
}

function workspaceInfo(
	id: string,
	branch: string,
	directory: string,
): {
	id: string;
	type: string;
	name: string;
	branch: string;
	directory: string;
	extra: null;
	projectID: string;
} {
	return {
		id,
		type: "ocx-git-worktree",
		name: branch,
		branch,
		directory,
		extra: null,
		projectID: "project-test",
	};
}

const validInProgressPlan = `---
status: in-progress
phase: 2
updated: 2026-08-21
---

# Implementation Plan

## Goal
Deliver a validated orchestration boundary safely

## Context & Decisions
| Decision | Rationale | Source |
|----------|-----------|--------|

## Phase 1: Discovery [COMPLETE]
- [x] 1.1 Confirm the intended boundary

## Phase 2: Implementation [IN PROGRESS]
- [ ] **2.1 Enforce the boundary** ← CURRENT
- [ ] 2.2 Verify the boundary

## Notes
- 2026-08-21: No delegated research was required
`;

const validCompletePlan = `---
status: complete
phase: 1
updated: 2026-08-21
---

# Implementation Plan

## Goal
Deliver a completed and validated implementation

## Context & Decisions
| Decision | Rationale | Source |
|----------|-----------|--------|

## Phase 1: Delivery [COMPLETE]
- [x] 1.1 Complete implementation

## Notes
- 2026-08-21: Delivery verified
`;

describe("permission and delegation enforcement", () => {
	test("does not classify wildcard deny with an allow exception as read-only", () => {
		const internals = backgroundAgentsPlugin.testInternals;
		const globalPermission = {
			"*": "deny",
			edit: "deny",
			write: "deny",
			bash: "deny",
			"oc_*": "deny",
			shell: "deny",
			mkdir: "deny",
			rm: "deny",
			task: "deny",
			delegate: "deny",
			"plan_*": "deny",
			"worktree_*": "deny",
		} as const;

		expect(internals.isAgentPermissionReadOnly(globalPermission, {})).toBe(
			true,
		);
		expect(
			internals.isAgentPermissionReadOnly(globalPermission, {
				bash: { "*": "deny", "git branch*": "allow" },
			}),
		).toBe(false);
		expect(
			internals.isPermissionCompletelyDenied({
				"*": "deny",
				"gh api *": "allow",
			}),
		).toBe(false);
	});

	test("allows coder Git inspection but rejects repository mutations", () => {
		const internals = backgroundAgentsPlugin.testInternals;
		expect(
			internals.isForcePushCommand("git push --force origin feature/x"),
		).toBe(true);
		expect(
			internals.isForcePushCommand(
				"git push origin feature/x --force-with-lease",
			),
		).toBe(true);
		expect(internals.isForcePushCommand("git push origin feature/x")).toBe(
			false,
		);
		expect(
			internals.coderShellPolicyViolation("git -C repo commit -m test"),
		).toContain("build orchestrator");
		for (const command of [
			"git branch --show-current",
			"git branch -a --no-color",
			"git remote -v",
			"git stash list",
			"git tag --list",
			"git worktree list --porcelain",
			"git branch --show-current && git diff --stat main...HEAD",
			"git --no-pager branch --show-current",
			"git log --grep worktree --oneline",
		]) {
			expect(internals.coderShellPolicyViolation(command), command).toBeNull();
		}
		for (const command of [
			"git branch -D old-branch",
			"git remote add upstream https://example.invalid/repo.git",
			"git remote -v add upstream https://example.invalid/repo.git",
			"git stash push -m temporary",
			"git tag v1.0.0",
			"git tag --list --delete v1.0.0",
			"git branch --list --delete old-branch",
			"git worktree remove ../other",
			"git -C ../other status --short",
			"git --git-dir=../other/.git status --short",
			"git --no-pager branch -D old-branch",
		]) {
			expect(
				internals.coderShellPolicyViolation(command),
				command,
			).not.toBeNull();
		}
		expect(internals.coderShellPolicyViolation("bun test")).toBeNull();
		expect(internals.isBuildShellMutation("git status --short")).toBe(false);
		expect(internals.isBuildShellMutation("git add README.md")).toBe(true);
		expect(internals.isBuildShellMutation("git rebase main")).toBe(true);
	});

	test("uses runtime default-deny and explicit role capabilities", async () => {
		const config = await readConfig();
		expect(config.permission).toMatchObject({
			"*": "deny",
			external_directory: "deny",
			bash: "deny",
			edit: "deny",
			write: "deny",
			apply_patch: "deny",
			"oc_*": "deny",
			shell: "deny",
			mkdir: "deny",
			rm: "deny",
			task: "deny",
			delegate: "deny",
			"plan_*": "deny",
			"worktree_*": "deny",
			websearch: "deny",
			skill: "deny",
		});
		for (const name of ["researcher", "reviewer", "explore"]) {
			expect(config.agent?.[name]?.permission?.bash).toBe("deny");
		}
		expect(config.agent?.plan?.permission?.task).toEqual({
			"*": "deny",
		});
		expect(config.agent?.build?.permission?.task).toEqual({
			"*": "deny",
			coder: "allow",
			scribe: "allow",
		});
		expect(config.agent?.coder?.permission?.delegate).toBeUndefined();
		expect(config.agent?.coder?.permission?.apply_patch).toBe("allow");
		const coderBash = config.agent?.coder?.permission?.bash as Record<
			string,
			string
		>;
		expect(coderBash).toMatchObject({
			"*": "allow",
			"git branch*": "deny",
			"git branch --show-current*": "allow",
			"git remote*": "deny",
			"git remote -v*": "allow",
			"git stash*": "deny",
			"git stash list*": "allow",
			"git tag*": "deny",
			"git tag --list*": "allow",
			"git worktree*": "deny",
			"git worktree list*": "allow",
		});
		for (const [denyRule, allowRule] of [
			["git branch*", "git branch --show-current*"],
			["git remote*", "git remote -v*"],
			["git stash*", "git stash list*"],
			["git tag*", "git tag --list*"],
			["git worktree*", "git worktree list*"],
		] as const) {
			expect(Object.keys(coderBash).indexOf(allowRule)).toBeGreaterThan(
				Object.keys(coderBash).indexOf(denyRule),
			);
		}
		expect(config.agent?.scribe?.permission?.apply_patch).toBe("allow");
		expect(config.agent?.scribe?.permission?.write).toBeInstanceOf(Object);
		expect(config.agent?.scribe?.permission?.external_directory).toMatchObject({
			"*": "deny",
			"/tmp/**": "allow",
			"/private/tmp/**": "allow",
		});
		expect(config.agent?.build?.permission?.external_directory).toMatchObject({
			"*": "deny",
			"~/.local/share/opencode/worktree/**": "allow",
			"/tmp/**": "allow",
			"/private/tmp/**": "allow",
		});
		expect(config.agent?.build?.permission?.bash).toMatchObject({
			"*": "deny",
			"git branch -a --no-color": "allow",
			"git worktree list*": "allow",
			"git show*": "allow",
			"git remote -v*": "allow",
			"git add*": "ask",
			"git rebase*": "ask",
			"git push*--force*": "deny",
		});
		expect(config.agent?.build?.prompt).toContain(
			"Rebase only when the user explicitly requests it",
		);
		expect(config.agent?.build?.prompt).toContain(
			"call `delegate` for the read-only `explore`, `researcher`, and `reviewer` agents",
		);
		expect(config.agent?.build?.prompt).toContain(
			"Never call `task` for `reviewer`",
		);
		expect(config.agent?.build?.prompt).toContain(
			'call `delegate` with `agent: "reviewer"`',
		);
		expect(config.agent?.plan?.permission?.compress).toBe("allow");
		expect(config.agent?.build?.permission?.compress).toBe("allow");
		for (const name of [
			"researcher",
			"scribe",
			"coder",
			"reviewer",
			"explore",
		]) {
			expect(config.agent?.[name]?.permission?.compress, name).toBe("deny");
		}
		expect(config.agent?.general?.disable).toBe(true);
		expect(config.disabled_providers).toContain("cursor-acp");
		expect(config.provider?.["cursor-acp"]).toBeUndefined();
		expect(config.plugin?.some((plugin) => plugin.includes("cursor"))).toBe(
			false,
		);
	});

	test("keeps local reads, MCPs, worktrees, skills, and commands role-scoped", async () => {
		const config = await readConfig();
		for (const name of ["scribe", "coder", "reviewer", "build", "explore"]) {
			expect(config.agent?.[name]?.permission?.read, name).toMatchObject({
				"*": "allow",
				"mcp:*": "deny",
			});
		}

		expect(config.agent?.researcher?.permission).toMatchObject({
			"context7_*": "allow",
			"exa_*": "allow",
			"gh_grep_*": "allow",
			webfetch: "allow",
			read: "deny",
			bash: "deny",
			skill: "deny",
		});
		expect(config.agent?.researcher?.permission?.websearch).toBeUndefined();
		expect(config.agent?.explore?.permission).toMatchObject({
			"codegraph_*": "allow",
			"context7_*": "deny",
			"exa_*": "deny",
			"gh_grep_*": "deny",
			bash: "deny",
			skill: "deny",
		});
		expect(config.agent?.coder?.permission).toMatchObject({
			"codegraph_*": "allow",
			"context7_*": "deny",
			"exa_*": "deny",
			"gh_grep_*": "deny",
		});
		expect(config.agent?.build?.permission).toMatchObject({
			worktree_create: "allow",
			"worktree_*": "allow",
			worktree_delete: "ask",
		});
		const runtimeContract = await Bun.file(
			new URL("../tools/runtime.md", import.meta.url),
		).text();
		expect(runtimeContract).toContain("## Build Runtime Tools");
		expect(runtimeContract).toContain(
			"Generic MCP resource list/read tools are deliberately hidden",
		);
		for (const name of [
			"plan",
			"explore",
			"researcher",
			"coder",
			"reviewer",
			"scribe",
		]) {
			expect(config.agent?.[name]?.permission?.worktree_create, name).not.toBe(
				"allow",
			);
		}

		expect(config.instructions).toContain(
			"{env:OPENCODE_CONFIG_DIR}/tools/capabilities.md",
		);
		expect(config.plugin).toContain("./plugins/ocx/runtime-guard.ts");
		const capabilityMatrix = await Bun.file(
			new URL("../tools/capabilities.md", import.meta.url),
		).text();
		expect(capabilityMatrix).toContain("`codegraph_codegraph_explore`");
		expect(capabilityMatrix).toContain("`context7_resolve-library-id`");
		expect(capabilityMatrix).toContain("A dirty default checkout is not a creation blocker");
		expect(capabilityMatrix).toContain("`list_mcp_resources`");
		expect(capabilityMatrix).toContain("`git -C`");

		const reviewCommand = await Bun.file(
			new URL("../commands/review.md", import.meta.url),
		).text();
		expect(reviewCommand).toMatch(/^---\ndescription:.*\nagent: build\n---/);
	});

	test("hides generic MCP resource probes from every managed message", async () => {
		const plugin = await runtimeGuardPlugin({} as never);
		const hook = plugin["chat.message"];
		if (!hook) throw new Error("runtime guard chat.message hook is missing");
		for (const agent of [
			"plan",
			"build",
			"explore",
			"researcher",
			"coder",
			"reviewer",
			"scribe",
		]) {
			const output = {
				message: {
					agent,
					tools: { worktree_create: true },
				},
				parts: [],
			};

			await hook({ sessionID: "session", agent }, output as never);

			expect(output.message.tools, agent).toEqual({
				worktree_create: true,
				list_mcp_resources: false,
				list_mcp_resource_templates: false,
				read_mcp_resource: false,
			});
		}
	});

	test("blocks shell for a read-only agent even if a future config regresses", async () => {
		const home = await mkdtemp(
			path.join(os.tmpdir(), "opencode-permission-home-"),
		);
		const directory = await mkdtemp(
			path.join(os.tmpdir(), "opencode-permission-project-"),
		);
		const previousHome = process.env.HOME;
		process.env.HOME = home;
		try {
			const config = await readConfig();
			const plugin = await backgroundAgentsPlugin({
				directory,
				client: createAgentClient(config, "reviewer"),
			} as never);
			const hook = plugin["tool.execute.before"];
			if (!hook) throw new Error("permission hook is missing");
			await expect(
				hook(
					{ tool: "bash", sessionID: "reviewer-session" },
					{ args: { command: "cat README.md > changed.md" } },
				),
			).rejects.toThrow("not allowed to execute shell");
			await expect(
				hook({ tool: "oc_write", sessionID: "reviewer-session" }, { args: {} }),
			).rejects.toThrow("Provider tool alias");
			await expect(
				hook(
					{ tool: "apply_patch", sessionID: "reviewer-session" },
					{ args: {} },
				),
			).rejects.toThrow("authorized write leaf");
		} finally {
			if (previousHome === undefined) delete process.env.HOME;
			else process.env.HOME = previousHome;
			await rm(home, { recursive: true, force: true });
			await rm(directory, { recursive: true, force: true });
		}
	});

	test("blocks a coder mutation from the default checkout", async () => {
		const home = await mkdtemp(path.join(os.tmpdir(), "opencode-coder-home-"));
		const { repository, worktree } = await createGitRepository(
			"opencode-coder-default",
		);
		const previousHome = process.env.HOME;
		process.env.HOME = home;
		try {
			const config = await readConfig();
			const plugin = await backgroundAgentsPlugin({
				directory: repository,
				client: createAgentClient(config, "coder"),
			} as never);
			const hook = plugin["tool.execute.before"];
			if (!hook) throw new Error("permission hook is missing");
			await expect(
				hook({ tool: "edit", sessionID: "coder-session" }, { args: {} }),
			).rejects.toThrow("managed, non-default worktree");
			await expect(
				hook(
					{ tool: "apply_patch", sessionID: "coder-session" },
					{
						args: {
							patchText:
								"*** Begin Patch\n*** Update File: README.md\n*** End Patch",
						},
					},
				),
			).rejects.toThrow("managed, non-default worktree");
		} finally {
			if (previousHome === undefined) delete process.env.HOME;
			else process.env.HOME = previousHome;
			await runCommand(
				["git", "worktree", "remove", "--force", worktree],
				repository,
			).catch(() => undefined);
			await rm(repository, { recursive: true, force: true });
			await rm(home, { recursive: true, force: true });
		}
	});

	test("enforces the scribe documentation extension at runtime", async () => {
		const home = await mkdtemp(path.join(os.tmpdir(), "opencode-scribe-home-"));
		const directory = await mkdtemp(
			path.join(os.tmpdir(), "opencode-scribe-project-"),
		);
		const previousHome = process.env.HOME;
		process.env.HOME = home;
		try {
			const config = await readConfig();
			const plugin = await backgroundAgentsPlugin({
				directory,
				client: createAgentClient(config, "scribe"),
			} as never);
			const hook = plugin["tool.execute.before"];
			if (!hook) throw new Error("permission hook is missing");
			await expect(
				hook(
					{ tool: "write", sessionID: "scribe-session" },
					{ args: { filePath: "src/application.ts" } },
				),
			).rejects.toThrow("documentation files");
		} finally {
			if (previousHome === undefined) delete process.env.HOME;
			else process.env.HOME = previousHome;
			await rm(home, { recursive: true, force: true });
			await rm(directory, { recursive: true, force: true });
		}
	});

	test("allows scribe patches only for documentation in the managed lease or a trusted handoff", async () => {
		const home = await mkdtemp(
			path.join(os.tmpdir(), "opencode-scribe-patch-home-"),
		);
		const { repository, worktree } = await createGitRepository(
			"opencode-scribe-patch",
		);
		const previousHome = process.env.HOME;
		process.env.HOME = home;
		try {
			const state = await initStateDb(worktree);
			claimSession(state, {
				id: "scribe-session",
				branch: "feature/test",
				path: worktree,
				workspaceId: "workspace-scribe-patch",
				createdAt: new Date().toISOString(),
			});
			state.close();

			const plugin = await backgroundAgentsPlugin({
				directory: worktree,
				client: createAgentClient(await readConfig(), "scribe"),
			} as never);
			const hook = plugin["tool.execute.before"];
			if (!hook) throw new Error("permission hook is missing");

			await expect(
				hook(
					{ tool: "apply_patch", sessionID: "scribe-session" },
					{
						args: {
							patchText:
								"*** Begin Patch\n*** Update File: README.md\n*** End Patch",
						},
					},
				),
			).resolves.toBeUndefined();
			await expect(
				hook(
					{ tool: "apply_patch", sessionID: "scribe-session" },
					{
						args: {
							patchText:
								"*** Begin Patch\n*** Update File: src/application.ts\n*** End Patch",
						},
					},
				),
			).rejects.toThrow("documentation files");
			await expect(
				hook(
					{ tool: "apply_patch", sessionID: "scribe-session" },
					{
						args: {
							patchText: `*** Begin Patch\n*** Update File: ${path.join(repository, "outside.md")}\n*** End Patch`,
						},
					},
				),
			).rejects.toThrow("escapes the managed worktree");
			await expect(
				hook(
					{ tool: "apply_patch", sessionID: "scribe-session" },
					{
						args: {
							patchText: `*** Begin Patch\n*** Add File: ${path.join(os.tmpdir(), "scribe-runtime-handoff.md")}\n*** End Patch`,
						},
					},
				),
			).resolves.toBeUndefined();
		} finally {
			if (previousHome === undefined) delete process.env.HOME;
			else process.env.HOME = previousHome;
			await runCommand(
				["git", "worktree", "remove", "--force", worktree],
				repository,
			).catch(() => undefined);
			await rm(repository, { recursive: true, force: true });
			await rm(home, { recursive: true, force: true });
		}
	});

	test("rejects unsafe persistence identifiers and fails closed on unknown task mode", async () => {
		expect(() => assertSafeStorageSegment("../session", "Session ID")).toThrow(
			"only letters",
		);
		expect(assertSafeStorageSegment("ses_safe-123", "Session ID")).toBe(
			"ses_safe-123",
		);

		const directory = await mkdtemp(
			path.join(os.tmpdir(), "opencode-task-mode-project-"),
		);
		const config = await readConfig();
		const client = createAgentClient(config, "build") as OpencodeClient & {
			app: { agents: () => Promise<never> };
		};
		client.app.agents = async () => {
			throw new Error("agent catalog unavailable");
		};
		try {
			const plugin = await backgroundAgentsPlugin({
				directory,
				client,
			} as never);
			const hook = plugin["tool.execute.before"];
			if (!hook) throw new Error("permission hook is missing");
			await expect(
				hook(
					{ tool: "task", sessionID: "build-session" },
					{ args: { subagent_type: "explore" } },
				),
			).rejects.toThrow("Cannot authorize native task");
		} finally {
			await rm(directory, { recursive: true, force: true });
		}
	});

	test("redirects reviewer task calls to the read-only delegate route", async () => {
		const directory = await mkdtemp(
			path.join(os.tmpdir(), "opencode-reviewer-task-route-"),
		);
		try {
			const config = await readConfig();
			const plugin = await backgroundAgentsPlugin({
				directory,
				client: createAgentClient(config, "build"),
			} as never);
			const hook = plugin["tool.execute.before"];
			if (!hook) throw new Error("permission hook is missing");
			await expect(
				hook(
					{ tool: "task", sessionID: "build-session" },
					{ args: { subagent_type: "reviewer" } },
				),
			).rejects.toThrow('Call delegate with agent: "reviewer"');
		} finally {
			await rm(directory, { recursive: true, force: true });
		}
	});

	test("keeps direct mutation targets inside the leased worktree", async () => {
		const home = await mkdtemp(path.join(os.tmpdir(), "opencode-target-home-"));
		const outside = await mkdtemp(
			path.join(os.tmpdir(), "opencode-target-outside-"),
		);
		const { repository, worktree } = await createGitRepository(
			"opencode-target-boundary",
		);
		const previousHome = process.env.HOME;
		process.env.HOME = home;
		try {
			await symlink(outside, path.join(worktree, "outside-link"), "dir");
			const state = await initStateDb(worktree);
			claimSession(state, {
				id: "coder-session",
				branch: "feature/test",
				path: worktree,
				workspaceId: "workspace-target",
				createdAt: new Date().toISOString(),
			});
			state.close();

			const config = await readConfig();
			const plugin = await backgroundAgentsPlugin({
				directory: worktree,
				client: createAgentClient(config, "coder"),
			} as never);
			const hook = plugin["tool.execute.before"];
			if (!hook) throw new Error("permission hook is missing");

			await expect(
				hook(
					{ tool: "write", sessionID: "coder-session" },
					{ args: { filePath: "../escape.ts" } },
				),
			).rejects.toThrow("escapes the managed worktree");
			await expect(
				hook(
					{ tool: "edit", sessionID: "coder-session" },
					{ args: { filePath: "outside-link/escape.ts" } },
				),
			).rejects.toThrow("through a symlink");
			await expect(
				hook(
					{ tool: "apply_patch", sessionID: "coder-session" },
					{
						args: {
							patchText:
								"*** Begin Patch\n*** Add File: ../escape.ts\n+bad\n*** End Patch",
						},
					},
				),
			).rejects.toThrow("escapes the managed worktree");
			await expect(
				hook(
					{ tool: "write", sessionID: "coder-session" },
					{ args: { filePath: "src/inside.ts" } },
				),
			).resolves.toBeUndefined();
			await expect(
				hook(
					{ tool: "bash", sessionID: "coder-session" },
					{ args: { command: "bun test", cwd: "../" } },
				),
			).rejects.toThrow("shell working directory");
			await expect(
				hook(
					{ tool: "bash", sessionID: "coder-session" },
					{ args: { command: "bun test", workdir: "outside-link" } },
				),
			).rejects.toThrow("through a symlink");
			await expect(
				hook(
					{ tool: "bash", sessionID: "coder-session" },
					{ args: { command: "bun test", cwd: "src" } },
				),
			).resolves.toBeUndefined();
		} finally {
			if (previousHome === undefined) delete process.env.HOME;
			else process.env.HOME = previousHome;
			await runCommand(
				["git", "worktree", "remove", "--force", worktree],
				repository,
			).catch(() => undefined);
			await rm(repository, { recursive: true, force: true });
			await rm(home, { recursive: true, force: true });
			await rm(outside, { recursive: true, force: true });
		}
	});

	test("allows build to inspect another managed worktree but not mutate it", async () => {
		const home = await mkdtemp(
			path.join(os.tmpdir(), "opencode-managed-inspection-home-"),
		);
		const otherWorktree = await mkdtemp(
			path.join(os.tmpdir(), "opencode-managed-inspection-other-"),
		);
		const { repository, worktree } = await createGitRepository(
			"opencode-managed-inspection",
		);
		const previousHome = process.env.HOME;
		process.env.HOME = home;
		try {
			const state = await initStateDb(worktree);
			claimSession(state, {
				id: "build-session",
				branch: "feature/test",
				path: worktree,
				workspaceId: "workspace-current",
				createdAt: new Date().toISOString(),
			});
			claimSession(state, {
				id: "other-session",
				branch: "feature/other",
				path: otherWorktree,
				workspaceId: "workspace-other",
				createdAt: new Date().toISOString(),
			});
			state.close();

			const plugin = await backgroundAgentsPlugin({
				directory: worktree,
				client: createAgentClient(await readConfig(), "build"),
			} as never);
			const hook = plugin["tool.execute.before"];
			if (!hook) throw new Error("permission hook is missing");
			await expect(
				hook(
					{ tool: "bash", sessionID: "build-session" },
					{ args: { command: "git status --short", cwd: otherWorktree } },
				),
			).resolves.toBeUndefined();
			await expect(
				hook(
					{ tool: "bash", sessionID: "build-session" },
					{ args: { command: "git add README.md", cwd: otherWorktree } },
				),
			).rejects.toThrow("shell working directory");
			await expect(
				hook(
					{ tool: "bash", sessionID: "build-session" },
					{
						args: {
							command:
								"git remote -v add upstream https://example.invalid/repo.git",
						},
					},
				),
			).rejects.toThrow("Build shell command rejected");
		} finally {
			if (previousHome === undefined) delete process.env.HOME;
			else process.env.HOME = previousHome;
			await runCommand(
				["git", "worktree", "remove", "--force", worktree],
				repository,
			).catch(() => undefined);
			await rm(repository, { recursive: true, force: true });
			await rm(otherWorktree, { recursive: true, force: true });
			await rm(home, { recursive: true, force: true });
		}
	});

	test("allows scribe handoff documents only in trusted temporary storage", async () => {
		const home = await mkdtemp(
			path.join(os.tmpdir(), "opencode-scribe-handoff-home-"),
		);
		const { repository, worktree } = await createGitRepository(
			"opencode-scribe-handoff",
		);
		const previousHome = process.env.HOME;
		process.env.HOME = home;
		try {
			const state = await initStateDb(worktree);
			claimSession(state, {
				id: "build-session",
				branch: "feature/test",
				path: worktree,
				workspaceId: "workspace-handoff",
				createdAt: new Date().toISOString(),
			});
			state.close();
			const plugin = await backgroundAgentsPlugin({
				directory: worktree,
				client: createAgentClient(await readConfig(), "scribe", {
					parentID: "build-session",
				}),
			} as never);
			const hook = plugin["tool.execute.before"];
			if (!hook) throw new Error("permission hook is missing");
			await expect(
				hook(
					{ tool: "write", sessionID: "scribe-session" },
					{
						args: { filePath: path.join(os.tmpdir(), "opencode-handoff.md") },
					},
				),
			).resolves.toBeUndefined();
			await expect(
				hook(
					{ tool: "write", sessionID: "scribe-session" },
					{ args: { filePath: path.join(os.tmpdir(), "notes.md") } },
				),
			).rejects.toThrow("escapes the managed worktree");
		} finally {
			if (previousHome === undefined) delete process.env.HOME;
			else process.env.HOME = previousHome;
			await runCommand(
				["git", "worktree", "remove", "--force", worktree],
				repository,
			).catch(() => undefined);
			await rm(repository, { recursive: true, force: true });
			await rm(home, { recursive: true, force: true });
		}
	});
});

describe("exclusive and durable workspace lifecycle", () => {
	test("enforces exclusive leases for branch, path, and workspace", () => {
		const database = createStateDatabase();
		claimSession(database, {
			id: "owner",
			branch: "feature/exclusive",
			path: "/tmp/exclusive",
			workspaceId: "workspace-owner",
			createdAt: new Date().toISOString(),
		});
		expect(() =>
			claimSession(database, {
				id: "competitor",
				branch: "feature/exclusive",
				path: "/tmp/other",
				workspaceId: "workspace-other",
				createdAt: new Date().toISOString(),
			}),
		).toThrow();
		expect(getSession(database, "owner")?.workspaceId).toBe("workspace-owner");
		database.close();
	});

	test("keeps pending deletions isolated by session", () => {
		const database = createStateDatabase();
		for (const suffix of ["one", "two"]) {
			claimSession(database, {
				id: suffix,
				branch: `feature/${suffix}`,
				path: `/tmp/${suffix}`,
				workspaceId: `workspace-${suffix}`,
				createdAt: new Date().toISOString(),
			});
			setPendingDelete(database, {
				sessionId: suffix,
				branch: `feature/${suffix}`,
				path: `/tmp/${suffix}`,
			});
		}
		expect(getPendingDelete(database, "one")?.branch).toBe("feature/one");
		expect(getPendingDelete(database, "two")?.branch).toBe("feature/two");
		clearPendingDelete(database, "one");
		expect(getPendingDelete(database, "one")).toBeNull();
		expect(getPendingDelete(database, "two")?.branch).toBe("feature/two");
		database.close();
	});

	test("claims and persists continuation before native warp", async () => {
		const database = createStateDatabase();
		const order: string[] = [];
		const result = await worktreePlugin.testInternals.bindSessionToWorkspace({
			database,
			sessionId: "parent-session",
			branch: "feature/shared-workspace",
			createWorkspace: async () => ({
				workspace: workspaceInfo(
					"workspace-1",
					"feature/shared-workspace",
					"/tmp/shared-workspace",
				),
				created: true,
			}),
			warpSession: async () => {
				order.push(
					getSession(database, "parent-session") ? "claimed" : "unclaimed",
				);
				order.push(
					getPendingContinuation(database, "parent-session")
						? "durable"
						: "volatile",
				);
			},
			removeWorkspace: async () => order.push("removed"),
			log: { debug() {}, info() {}, warn() {}, error() {} },
		});
		expect(result.ok).toBe(true);
		expect(order).toEqual(["claimed", "durable"]);
		database.close();
	});

	test("does not remove a reused workspace when binding fails", async () => {
		const database = createStateDatabase();
		let removeCount = 0;
		const result = await worktreePlugin.testInternals.bindSessionToWorkspace({
			database,
			sessionId: "parent-session",
			branch: "fix/warp-failure",
			createWorkspace: async () => ({
				workspace: workspaceInfo(
					"workspace-2",
					"fix/warp-failure",
					"/tmp/warp-failure",
				),
				created: false,
			}),
			warpSession: async () => {
				throw new Error("workspace API unavailable");
			},
			removeWorkspace: async () => {
				removeCount++;
			},
			log: { debug() {}, info() {}, warn() {}, error() {} },
		});
		expect(result.ok).toBe(false);
		if (!result.ok) expect(result.error).toContain("workspace API unavailable");
		expect(removeCount).toBe(0);
		expect(getSession(database, "parent-session")).toBeNull();
		expect(getPendingContinuation(database, "parent-session")).toBeNull();
		database.close();
	});

	test("rejects a branch already leased by another root before workspace creation", async () => {
		const database = createStateDatabase();
		claimSession(database, {
			id: "owner",
			branch: "feature/shared",
			path: "/tmp/owner",
			workspaceId: "workspace-owner",
			createdAt: new Date().toISOString(),
		});
		let createCalled = false;
		const result = await worktreePlugin.testInternals.bindSessionToWorkspace({
			database,
			sessionId: "competitor",
			branch: "feature/shared",
			createWorkspace: async () => {
				createCalled = true;
				return {
					workspace: workspaceInfo(
						"workspace-new",
						"feature/shared",
						"/tmp/new",
					),
					created: true,
				};
			},
			warpSession: async () => undefined,
			removeWorkspace: async () => undefined,
			log: { debug() {}, info() {}, warn() {}, error() {} },
		});
		expect(result.ok).toBe(false);
		if (!result.ok)
			expect(result.error).toContain("already leased by session owner");
		expect(createCalled).toBe(false);
		database.close();
	});

	test("resumes a persisted continuation once and retains it after failure", async () => {
		const database = createStateDatabase();
		claimSession(database, {
			id: "parent",
			branch: "feature/resume",
			path: "/tmp/resume",
			workspaceId: "workspace-resume",
			createdAt: new Date().toISOString(),
		});
		setPendingContinuation(database, {
			sessionId: "parent",
			workspaceId: "workspace-resume",
		});
		const resumed: string[] = [];
		const log = { debug() {}, info() {}, warn() {}, error() {} };
		expect(
			await worktreePlugin.testInternals.resumePendingContinuation(
				database,
				"parent",
				async (sessionId, workspaceId) =>
					resumed.push(`${sessionId}:${workspaceId}`),
				log,
			),
		).toBe(true);
		expect(getPendingContinuation(database, "parent")).toBeNull();
		expect(
			await worktreePlugin.testInternals.resumePendingContinuation(
				database,
				"parent",
				async () => undefined,
				log,
			),
		).toBe(false);

		setPendingContinuation(database, {
			sessionId: "parent",
			workspaceId: "workspace-resume",
		});
		await worktreePlugin.testInternals.resumePendingContinuation(
			database,
			"parent",
			async () => {
				throw new Error("temporary failure");
			},
			log,
		);
		expect(getPendingContinuation(database, "parent")?.workspaceId).toBe(
			"workspace-resume",
		);
		expect(resumed).toEqual(["parent:workspace-resume"]);
		database.close();
	});

	test("allows only one concurrent continuation dispatcher", async () => {
		const database = createStateDatabase();
		claimSession(database, {
			id: "parent",
			branch: "feature/concurrent-resume",
			path: "/tmp/concurrent-resume",
			workspaceId: "workspace-concurrent-resume",
			createdAt: new Date().toISOString(),
		});
		setPendingContinuation(database, {
			sessionId: "parent",
			workspaceId: "workspace-concurrent-resume",
		});
		let sends = 0;
		let release: (() => void) | undefined;
		const gate = new Promise<void>((resolve) => {
			release = resolve;
		});
		const log = { debug() {}, info() {}, warn() {}, error() {} };
		const first = worktreePlugin.testInternals.resumePendingContinuation(
			database,
			"parent",
			async () => {
				sends++;
				await gate;
			},
			log,
		);
		await Promise.resolve();
		const second = await worktreePlugin.testInternals.resumePendingContinuation(
			database,
			"parent",
			async () => {
				sends++;
			},
			log,
		);
		expect(second).toBe(false);
		release?.();
		expect(await first).toBe(true);
		expect(sends).toBe(1);
		expect(getPendingContinuation(database, "parent")).toBeNull();
		database.close();
	});

	test("defers native startup recovery until after plugin initialization", async () => {
		let recovered = false;
		const timer = worktreePlugin.testInternals.scheduleStartupRecovery(
			async () => {
				recovered = true;
			},
			{ debug() {}, info() {}, warn() {}, error() {} },
		);
		expect(recovered).toBe(false);
		await new Promise((resolve) => setTimeout(resolve, 10));
		expect(recovered).toBe(true);
		clearTimeout(timer);
	});

	test("retries startup recovery after a transient failure and then becomes idempotent", async () => {
		let attempts = 0;
		const recovery =
			worktreePlugin.testInternals.createRetryableStartupRecovery(
				async () => {
					attempts += 1;
					if (attempts === 1) throw new Error("transient native failure");
				},
				{ debug() {}, info() {}, warn() {}, error() {} },
			);
		expect(await recovery.ensure()).toBe(false);
		expect(recovery.isReady()).toBe(false);
		expect(await recovery.ensure()).toBe(true);
		expect(await recovery.ensure()).toBe(true);
		expect(attempts).toBe(2);
	});

	test("retains an authorized pending deletion after a transient native failure", async () => {
		const database = createStateDatabase();
		const { repository, worktree } = await createGitRepository(
			"opencode-delete-retry",
		);
		claimSession(database, {
			id: "delete-session",
			branch: "feature/test",
			path: worktree,
			workspaceId: "workspace-delete",
			createdAt: new Date().toISOString(),
		});
		setPendingDelete(database, {
			sessionId: "delete-session",
			branch: "feature/test",
			path: worktree,
		});
		const warps: Array<string | null> = [];
		const result = await worktreePlugin.testInternals.processPendingDelete({
			database,
			sessionId: "delete-session",
			mainRoot: repository,
			warpSession: async (workspaceId) => {
				warps.push(workspaceId);
			},
			removeNativeWorkspace: async () => {
				throw new Error("temporary API failure");
			},
			log: { debug() {}, info() {}, warn() {}, error() {} },
		});
		expect(result).toBe("retry");
		expect(warps).toEqual([null, "workspace-delete"]);
		expect(getPendingDelete(database, "delete-session")).not.toBeNull();
		database.close();
		await runCommand(
			["git", "worktree", "remove", "--force", worktree],
			repository,
		);
		await rm(repository, { recursive: true, force: true });
	});

	test("reconciles stale leases without deleting orphaned native workspaces", async () => {
		const database = createStateDatabase();
		const validPath = await mkdtemp(
			path.join(os.tmpdir(), "opencode-valid-lease-"),
		);
		claimSession(database, {
			id: "valid",
			branch: "feature/valid",
			path: validPath,
			workspaceId: "workspace-valid",
			createdAt: new Date().toISOString(),
		});
		claimSession(database, {
			id: "stale",
			branch: "feature/stale",
			path: "/tmp/definitely-missing-opencode-worktree",
			workspaceId: "workspace-stale",
			createdAt: new Date().toISOString(),
		});
		const result = await worktreePlugin.testInternals.reconcileWorkspaceState(
			database,
			[
				workspaceInfo("workspace-valid", "feature/valid", validPath),
				workspaceInfo("workspace-orphan", "feature/orphan", "/tmp/orphan"),
			],
			{ debug() {}, info() {}, warn() {}, error() {} },
		);
		expect(result.removedSessionIds).toEqual(["stale"]);
		expect(result.orphanedWorkspaceIds).toEqual(["workspace-orphan"]);
		expect(getSession(database, "valid")).not.toBeNull();
		expect(getSession(database, "stale")).toBeNull();
		database.close();
		await rm(validPath, { recursive: true, force: true });
	});

	test("uses one project ID across linked worktrees and different IDs across clones", async () => {
		const { repository, worktree } = await createGitRepository(
			"opencode-project-id",
		);
		const clone = `${repository}-clone`;
		try {
			await runCommand(
				["git", "clone", "-q", "--no-hardlinks", repository, clone],
				os.tmpdir(),
			);
			expect(await getProjectId(worktree)).toBe(await getProjectId(repository));
			expect(await getProjectId(clone)).not.toBe(
				await getProjectId(repository),
			);
		} finally {
			await runCommand(
				["git", "worktree", "remove", "--force", worktree],
				repository,
			).catch(() => undefined);
			await rm(repository, { recursive: true, force: true });
			await rm(clone, { recursive: true, force: true });
		}
	});

	test("rejects repository-controlled shell hooks", async () => {
		const repository = await mkdtemp(
			path.join(os.tmpdir(), "opencode-hook-config-"),
		);
		await mkdir(path.join(repository, ".opencode"));
		await Bun.write(
			path.join(repository, ".opencode", "worktree.jsonc"),
			'{ "hooks": { "postCreate": ["touch SHOULD_NOT_RUN"] } }',
		);
		const adapter = worktreePlugin.testInternals.createWorkspaceAdapter(
			repository,
			{
				debug() {},
				info() {},
				warn() {},
				error() {},
			},
		);
		await expect(
			adapter.configure({
				id: "workspace",
				type: "ocx-git-worktree",
				name: "workspace",
				branch: "feature/hooks",
				directory: null,
				extra: null,
				projectID: "project",
			}),
		).rejects.toThrow("Unrecognized key");
		expect(
			await Bun.file(path.join(repository, "SHOULD_NOT_RUN")).exists(),
		).toBe(false);
		await rm(repository, { recursive: true, force: true });
	});

	test("validates storage paths and native adapter branch inputs at their boundaries", async () => {
		const repository = await mkdtemp(
			path.join(os.tmpdir(), "opencode-adapter-boundary-"),
		);
		const adapter = worktreePlugin.testInternals.createWorkspaceAdapter(
			repository,
			{ debug() {}, info() {}, warn() {}, error() {} },
		);
		await expect(
			adapter.configure({
				id: "workspace",
				type: "ocx-git-worktree",
				name: "workspace",
				branch: "../escape",
				directory: null,
				extra: null,
				projectID: "project",
			}),
		).rejects.toThrow("Invalid workspace branch");
		await expect(
			getWorktreePath(repository, "feature/test", "relative/worktrees"),
		).rejects.toThrow("must be absolute");
		await expect(
			getWorktreePath(repository, "../../escape", os.tmpdir()),
		).rejects.toThrow("escapes");
		expect(
			await getWorktreePath(
				repository,
				"feature/test",
				os.tmpdir(),
				"native-project",
			),
		).toBe(path.join(os.tmpdir(), "native-project", "feature/test"));
		await expect(
			getWorktreePath(
				repository,
				"feature/test",
				os.tmpdir(),
				"../invalid-project",
			),
		).rejects.toThrow("invalid native project ID");
		await rm(repository, { recursive: true, force: true });
	});

	test("drops an orphaned legacy pending deletion without violating foreign keys", async () => {
		const home = await mkdtemp(
			path.join(os.tmpdir(), "opencode-legacy-state-home-"),
		);
		const project = await mkdtemp(
			path.join(os.tmpdir(), "opencode-legacy-state-project-"),
		);
		const previousHome = process.env.HOME;
		process.env.HOME = home;
		try {
			const projectId = await getProjectId(project);
			const databaseDirectory = path.join(
				home,
				".local",
				"share",
				"opencode",
				"plugins",
				"worktree",
			);
			await mkdir(databaseDirectory, { recursive: true });
			const legacy = new Database(
				path.join(databaseDirectory, `${projectId}.sqlite`),
			);
			legacy.exec(`
				CREATE TABLE sessions (
					id TEXT PRIMARY KEY,
					branch TEXT NOT NULL,
					path TEXT NOT NULL,
					created_at TEXT NOT NULL
				);
				CREATE TABLE pending_operations (
					type TEXT NOT NULL,
					branch TEXT,
					path TEXT,
					session_id TEXT
				);
				INSERT INTO pending_operations (type, branch, path, session_id)
				VALUES ('delete', 'feature/ghost', '/tmp/ghost', 'ghost-session');
			`);
			legacy.close();

			const migrated = await initStateDb(project);
			const legacyTable = migrated
				.prepare(
					"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'pending_operations'",
				)
				.get();
			expect(legacyTable).toBeNull();
			expect(getAllPendingDeletes(migrated)).toEqual([]);
			migrated.close();
		} finally {
			if (previousHome === undefined) delete process.env.HOME;
			else process.env.HOME = previousHome;
			await rm(home, { recursive: true, force: true });
			await rm(project, { recursive: true, force: true });
		}
	});

	test("consolidates only equivalent duplicate legacy worktree leases", async () => {
		const home = await mkdtemp(
			path.join(os.tmpdir(), "opencode-duplicate-state-home-"),
		);
		const project = await mkdtemp(
			path.join(os.tmpdir(), "opencode-duplicate-state-project-"),
		);
		const previousHome = process.env.HOME;
		process.env.HOME = home;
		try {
			const projectId = await getProjectId(project);
			const databaseDirectory = path.join(
				home,
				".local",
				"share",
				"opencode",
				"plugins",
				"worktree",
			);
			await mkdir(databaseDirectory, { recursive: true });
			const legacy = new Database(
				path.join(databaseDirectory, `${projectId}.sqlite`),
			);
			legacy.exec(`
				CREATE TABLE sessions (
					id TEXT PRIMARY KEY,
					branch TEXT NOT NULL,
					path TEXT NOT NULL,
					created_at TEXT NOT NULL,
					workspace_id TEXT
				);
				INSERT INTO sessions (id, branch, path, created_at, workspace_id)
				VALUES
					('legacy-session', 'feature/test', '/tmp/feature-test', '2026-08-20T00:00:00.000Z', NULL),
					('workspace-session', 'feature/test', '/tmp/feature-test', '2026-08-21T00:00:00.000Z', 'workspace-test');
			`);
			legacy.close();

			const migrated = await initStateDb(project);
			expect(getAllSessions(migrated)).toEqual([
				expect.objectContaining({
					id: "workspace-session",
					branch: "feature/test",
					workspaceId: "workspace-test",
				}),
			]);
			expect(() =>
				migrated
					.prepare(`
						INSERT INTO sessions (id, branch, path, created_at, workspace_id)
						VALUES ('conflict', 'feature/test', '/tmp/other', '2026-08-22T00:00:00.000Z', NULL)
					`)
					.run(),
			).toThrow();
			migrated.close();
		} finally {
			if (previousHome === undefined) delete process.env.HOME;
			else process.env.HOME = previousHome;
			await rm(home, { recursive: true, force: true });
			await rm(project, { recursive: true, force: true });
		}
	});

	test("never replaces a non-empty worktree directory with a symlink", async () => {
		const source = await mkdtemp(
			path.join(os.tmpdir(), "opencode-symlink-source-"),
		);
		const target = await mkdtemp(
			path.join(os.tmpdir(), "opencode-symlink-target-"),
		);
		await mkdir(path.join(source, "node_modules"));
		await Bun.write(path.join(source, "node_modules", "source.txt"), "source");
		await mkdir(path.join(target, "node_modules"));
		await Bun.write(path.join(target, "node_modules", "keep.txt"), "keep");

		await worktreePlugin.testInternals.symlinkDirs(
			source,
			target,
			["node_modules"],
			{ debug() {}, info() {}, warn() {}, error() {} },
		);

		expect((await lstat(path.join(target, "node_modules"))).isDirectory()).toBe(
			true,
		);
		expect(
			await Bun.file(path.join(target, "node_modules", "keep.txt")).text(),
		).toBe("keep");
		await rm(source, { recursive: true, force: true });
		await rm(target, { recursive: true, force: true });
	});

	test("removes a missing worktree's targeted Git registration", async () => {
		const { repository, worktree } = await createGitRepository(
			"opencode-missing-worktree",
		);
		try {
			await rm(worktree, { recursive: true, force: true });
			const adapter = worktreePlugin.testInternals.createWorkspaceAdapter(
				repository,
				{ debug() {}, info() {}, warn() {}, error() {} },
			);
			await adapter.remove({
				id: "workspace-missing",
				type: "ocx-git-worktree",
				name: "feature/test",
				branch: "feature/test",
				directory: worktree,
				extra: null,
				projectID: "native-project",
			});
			const listed = Bun.spawnSync(
				["git", "worktree", "list", "--porcelain"],
				{ cwd: repository },
			).stdout.toString();
			expect(listed).not.toContain(worktree);
		} finally {
			await rm(repository, { recursive: true, force: true });
		}
	});
});

describe("plan protocol and review coordination", () => {
	test("accepts lifecycle-consistent in-progress and complete plans", () => {
		expect(
			workspacePlugin.testInternals.parsePlanMarkdown(validInProgressPlan).ok,
		).toBe(true);
		expect(
			workspacePlugin.testInternals.parsePlanMarkdown(validCompletePlan).ok,
		).toBe(true);
		const withSupplementaryTraceability = validCompletePlan.replace(
			"## Notes",
			"## Acceptance Traceability\n| Outcome | Evidence |\n|---------|----------|\n| Delivered | Verified |\n\n## Notes",
		);
		expect(
			workspacePlugin.testInternals.parsePlanMarkdown(
				withSupplementaryTraceability,
			).ok,
		).toBe(true);
	});

	test("rejects missing context, missing current task, and multiple active phases", () => {
		const missingContext = validInProgressPlan.replace(
			/## Context & Decisions[\s\S]*?(?=## Phase 1)/,
			"",
		);
		const noCurrent = validInProgressPlan.replace(" ← CURRENT", "");
		const multiplePhases = validInProgressPlan.replace(
			"## Phase 1: Discovery [COMPLETE]",
			"## Phase 1: Discovery [IN PROGRESS]",
		);
		for (const plan of [missingContext, noCurrent, multiplePhases]) {
			expect(workspacePlugin.testInternals.parsePlanMarkdown(plan).ok).toBe(
				false,
			);
		}
	});

	test("requires every decision row to contain a delegation citation", () => {
		const plan = validInProgressPlan.replace(
			"|----------|-----------|--------|",
			"|----------|-----------|--------|\n| Use SQLite | Durable state | N/A |",
		);
		const result = workspacePlugin.testInternals.parsePlanMarkdown(plan);
		expect(result.ok).toBe(false);
		if (!result.ok)
			expect(result.error).toContain("Invalid delegation citation");
	});

	test("rejects ambiguous frontmatter, dates, tables, phase headings, and ordering", () => {
		const invalidPlans = [
			validInProgressPlan.replace("phase: 2", "phase: 2oops"),
			validInProgressPlan.replace("updated: 2026-08-21", "updated: 2026-02-31"),
			validInProgressPlan.replace(
				"|----------|-----------|--------|",
				"| Decision | Rationale | Source |",
			),
			validInProgressPlan.replace("[COMPLETE]", "[DONE]"),
			validInProgressPlan.replace("## Phase 2", "## Phase 3"),
			validInProgressPlan.replace(
				"- [ ] **2.1 Enforce the boundary** ← CURRENT\n- [ ] 2.2 Verify the boundary",
				"- [ ] **2.1 Enforce the boundary** ← CURRENT\n- [x] 2.2 Verify the boundary",
			),
		];
		for (const plan of invalidPlans) {
			expect(workspacePlugin.testInternals.parsePlanMarkdown(plan).ok).toBe(
				false,
			);
		}
	});

	test("verifies citation artifacts exist and are non-empty", async () => {
		const directory = await mkdtemp(
			path.join(os.tmpdir(), "opencode-citations-"),
		);
		await Bun.write(path.join(directory, "swift-amber-falcon.md"), "evidence");
		await Bun.write(path.join(directory, "empty-jade-owl.md"), "");
		const outside = path.join(os.tmpdir(), `outside-${randomUUID()}.md`);
		await Bun.write(outside, "outside evidence");
		await symlink(outside, path.join(directory, "linked-calm-owl.md"));
		expect(
			await workspacePlugin.testInternals.findMissingCitations(directory, [
				"ref:swift-amber-falcon",
				"ref:empty-jade-owl",
				"ref:missing-calm-otter",
				"ref:linked-calm-owl",
			]),
		).toEqual([
			"ref:empty-jade-owl",
			"ref:missing-calm-otter",
			"ref:linked-calm-owl",
		]);
		await rm(directory, { recursive: true, force: true });
		await rm(outside, { force: true });
	});

	test("tracks coder completion independently for each root session", () => {
		const calls = new Map([
			["call-a", { rootSessionID: "root-a", startTime: Date.now() }],
			["call-b", { rootSessionID: "root-b", startTime: Date.now() }],
		]);
		expect(
			workspacePlugin.testInternals.hasActiveCoderCallForRoot(calls, "root-a"),
		).toBe(true);
		calls.delete("call-a");
		expect(
			workspacePlugin.testInternals.hasActiveCoderCallForRoot(calls, "root-a"),
		).toBe(false);
		expect(
			workspacePlugin.testInternals.hasActiveCoderCallForRoot(calls, "root-b"),
		).toBe(true);
	});

	test("injects universal date awareness through the installed hook", async () => {
		const directory = await mkdtemp(
			path.join(os.tmpdir(), "opencode-workspace-project-"),
		);
		try {
			const plugin = await workspacePlugin({
				directory,
				client: createMinimalClient(),
			} as never);
			const hook = plugin["experimental.chat.system.transform"];
			if (!hook) throw new Error("system transform hook is missing");
			const output = { system: [] as string[] };
			await hook({ sessionID: "session" } as never, output);
			expect(output.system[0]).toContain("<date-awareness>");
		} finally {
			await rm(directory, { recursive: true, force: true });
		}
	});

	test("injects literal read-only reviewer routing", async () => {
		const directory = await mkdtemp(
			path.join(os.tmpdir(), "opencode-reviewer-routing-"),
		);
		try {
			const plugin = await backgroundAgentsPlugin({
				directory,
				client: createMinimalClient(),
			} as never);
			const hook = plugin["experimental.chat.system.transform"];
			if (!hook) throw new Error("delegation system transform is missing");
			const output = { system: [] as string[] };
			await hook({ sessionID: "build-session" } as never, output);
			const rules = output.system.join("\n");
			expect(rules).toContain(
				"| `explore`, `researcher`, `reviewer` | `delegate` |",
			);
			expect(rules).toContain("| `coder`, `scribe` | `task` |");
		} finally {
			await rm(directory, { recursive: true, force: true });
		}
	});
});

describe("deterministic plugin and dependency topology", () => {
	test("exposes only one executable export from every plugin entrypoint", async () => {
		const entrypoints = [
			"../plugins/ocx/project-instructions.ts",
			"../plugins/ocx/background-agents.ts",
			"../plugins/ocx/worktree.ts",
			"../plugins/ocx/workspace-plugin.ts",
			"../plugins/ocx/notify.ts",
			"../plugins/ocx/dcp.ts",
		];
		for (const entrypoint of entrypoints) {
			const module = await import(entrypoint);
			expect(Object.keys(module), entrypoint).toEqual(["default"]);
		}
	});

	test("loads local entrypoints explicitly before pinned external plugins", async () => {
		const config = await readConfig();
		expect(config.autoupdate).toBe("notify");
		expect(config.plugin?.slice(0, 7)).toEqual([
			"./plugins/ocx/project-instructions.ts",
			"./plugins/ocx/runtime-guard.ts",
			"./plugins/ocx/background-agents.ts",
			"./plugins/ocx/worktree.ts",
			"./plugins/ocx/workspace-plugin.ts",
			"./plugins/ocx/notify.ts",
			"./plugins/ocx/dcp.ts",
		]);
		expect(config.plugin).toContain("opencode-claude-auth@2.1.6");
		expect(config.plugin?.some((plugin) => plugin.includes("@latest"))).toBe(
			false,
		);
	});

	test("fails closed unless native project and external discovery are disabled", () => {
		expect(() =>
			assertControlledDiscoveryEnvironment({
				OPENCODE_DISABLE_PROJECT_CONFIG: "true",
				OPENCODE_DISABLE_EXTERNAL_SKILLS: "1",
				OPENCODE_DISABLE_CLAUDE_CODE_SKILLS: "true",
			}),
		).not.toThrow();
		expect(() =>
			assertControlledDiscoveryEnvironment({
				OPENCODE_DISABLE_PROJECT_CONFIG: "true",
			}),
		).toThrow("Controlled OpenCode discovery is not active");
	});

	test("loads hierarchical AGENTS.md and only follows in-repository file symlinks", async () => {
		const root = await mkdtemp(
			path.join(os.tmpdir(), "opencode-project-instructions-"),
		);
		const nested = path.join(root, "packages", "app");
		const outside = await mkdtemp(
			path.join(os.tmpdir(), "opencode-project-instructions-outside-"),
		);
		try {
			await mkdir(nested, { recursive: true });
			await Bun.write(path.join(root, "AGENTS.md"), "root instructions\n");
			await Bun.write(path.join(nested, "AGENTS.md"), "nested instructions\n");
			const instructions = await loadProjectInstructions(root, nested);
			expect(instructions.map((entry) => entry.content.trim())).toEqual([
				"root instructions",
				"nested instructions",
			]);

			await Bun.write(path.join(root, "CLAUDE.md"), "shared instructions\n");
			await rm(path.join(root, "AGENTS.md"));
			await symlink("CLAUDE.md", path.join(root, "AGENTS.md"), "file");
			const linkedInstructions = await loadProjectInstructions(root, nested);
			expect(linkedInstructions.map((entry) => entry.content.trim())).toEqual([
				"shared instructions",
				"nested instructions",
			]);

			const symlinkRoot = path.join(root, "symlink-project");
			await mkdir(symlinkRoot, { recursive: true });
			await Bun.write(path.join(outside, "AGENTS.md"), "outside\n");
			await symlink(
				path.join(outside, "AGENTS.md"),
				path.join(symlinkRoot, "AGENTS.md"),
				"file",
			);
			await expect(
				loadProjectInstructions(symlinkRoot, symlinkRoot),
			).rejects.toThrow("resolves outside the project root");
		} finally {
			await rm(root, { recursive: true, force: true });
			await rm(outside, { recursive: true, force: true });
		}
	});

	test("rejects repository DCP policy overrides", async () => {
		const project = await mkdtemp(
			path.join(os.tmpdir(), "opencode-project-dcp-"),
		);
		const managed = await mkdtemp(
			path.join(os.tmpdir(), "opencode-managed-dcp-"),
		);
		try {
			await mkdir(path.join(project, ".opencode"));
			await expect(
				assertNoProjectDcpOverride(project, managed),
			).resolves.toBeUndefined();
			await Bun.write(
				path.join(project, ".opencode", "dcp.jsonc"),
				'{ "experimental": { "allowSubAgents": true } }\n',
			);
			await expect(
				assertNoProjectDcpOverride(project, managed),
			).rejects.toThrow("Repository DCP overrides are disabled");
		} finally {
			await rm(project, { recursive: true, force: true });
			await rm(managed, { recursive: true, force: true });
		}
	});

	test("keeps DCP policy managed and primary-orchestrator only", async () => {
		const config = await readConfig();
		const dcp = parseJsonc(
			await Bun.file(new URL("../dcp.jsonc", import.meta.url)).text(),
		) as {
			autoUpdate?: boolean;
			experimental?: { allowSubAgents?: boolean; customPrompts?: boolean };
			compress?: { permission?: string; protectedTools?: string[] };
			strategies?: {
				deduplication?: { protectedTools?: string[] };
				purgeErrors?: { protectedTools?: string[] };
			};
		};

		expect(config.permission?.compress).toBe("allow");
		expect(config.agent?.plan?.permission?.compress).toBe("allow");
		expect(config.agent?.build?.permission?.compress).toBe("allow");
		for (const name of [
			"researcher",
			"scribe",
			"coder",
			"reviewer",
			"explore",
		]) {
			expect(config.agent?.[name]?.permission?.compress, name).toBe("deny");
		}
		expect(dcp.autoUpdate).toBe(false);
		expect(dcp.experimental).toEqual({
			allowSubAgents: false,
			customPrompts: false,
		});
		expect(dcp.compress?.permission).toBe("allow");
		for (const protectedTools of [
			dcp.compress?.protectedTools,
			dcp.strategies?.deduplication?.protectedTools,
			dcp.strategies?.purgeErrors?.protectedTools,
		]) {
			expect(protectedTools).toContain("delegation_read");
			expect(protectedTools).toContain("plan_save");
			expect(protectedTools).toContain("worktree_list");
			expect(protectedTools).toContain("worktree_inspect");
			expect(protectedTools).toContain("worktree_create");
		}
	});

	test("keeps the auto-scanned plugin root free of TypeScript entrypoints", async () => {
		const pluginRoot = new URL("../plugins", import.meta.url);
		const directTypeScriptFiles = (await readdir(pluginRoot)).filter((entry) =>
			entry.endsWith(".ts"),
		);
		expect(directTypeScriptFiles).toEqual([]);
	});

	test("uses argv-based notify-send without node-notifier", async () => {
		const invocations: string[][] = [];
		const sent = await sendLinuxNotifySendNotification(
			{ title: "OpenCode", subtitle: "Ready", message: "Needs attention" },
			{
				which: () => "/usr/bin/notify-send",
				spawnProcess: (argv) => {
					invocations.push(argv);
					return { exited: Promise.resolve(0) };
				},
			},
		);
		expect(sent).toBe(true);
		expect(invocations).toEqual([
			["/usr/bin/notify-send", "OpenCode — Ready", "Needs attention"],
		]);
	});
});
