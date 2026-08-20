import { Database } from "bun:sqlite"
import { describe, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import * as os from "node:os"
import * as path from "node:path"
import { parse as parseJsonc } from "jsonc-parser"

import type { OpencodeClient } from "./kdco-primitives/types"
import backgroundAgentsPlugin from "./background-agents"
import workspacePlugin from "./workspace-plugin"
import worktreePlugin from "./worktree"
import { addSession, getSession, initStateDb } from "./worktree/state"

const configPath = new URL("../opencode.jsonc", import.meta.url)

interface AgentConfig {
	prompt?: string
	permission?: {
		task?: string | Record<string, string>
	}
}

interface OpenCodeConfig {
	agent?: Record<string, AgentConfig>
}

async function readAgentPromptsFromConfig(): Promise<Record<string, string>> {
	const config = parseJsonc(await Bun.file(configPath).text()) as OpenCodeConfig
	const planPrompt = config.agent?.plan?.prompt
	const buildPrompt = config.agent?.build?.prompt

	if (!planPrompt || !buildPrompt) {
		throw new Error("Plan and build agent prompts must define worktree boundaries")
	}

	return { plan: planPrompt, build: buildPrompt }
}

function createClient(): OpencodeClient {
	return {
		app: {
			log: async () => undefined,
		},
	} as unknown as OpencodeClient
}

async function runCommand(command: string[], cwd: string): Promise<void> {
	const process = Bun.spawn(command, { cwd, stdout: "pipe", stderr: "pipe" })
	const [stdout, stderr, exitCode] = await Promise.all([
		new Response(process.stdout).text(),
		new Response(process.stderr).text(),
		process.exited,
	])
	if (exitCode !== 0) {
		throw new Error(`${command.join(" ")} failed: ${stderr.trim() || stdout.trim()}`)
	}
}

async function createGitRepository(prefix: string): Promise<{
	repository: string
	worktree: string
}> {
	const repository = await mkdtemp(path.join(os.tmpdir(), `${prefix}-repository-`))
	const worktree = `${repository}-worktree`
	await runCommand(["git", "init", "-q"], repository)
	await runCommand(["git", "config", "user.email", "tests@example.invalid"], repository)
	await runCommand(["git", "config", "user.name", "OpenCode tests"], repository)
	await Bun.write(path.join(repository, "README.md"), "test\n")
	await runCommand(["git", "add", "README.md"], repository)
	await runCommand(["git", "commit", "-qm", "initial"], repository)
	await runCommand(["git", "worktree", "add", "-qb", "feature/test", worktree, "HEAD"], repository)
	return { repository, worktree }
}

function createTaskClient(
	parentAgent: string | undefined,
	targetAgent: string,
	options: { lookupError?: boolean } = {},
): OpencodeClient {
	return {
		app: {
			log: async () => undefined,
		},
		session: {
			messages: async () => {
				if (options.lookupError) throw new Error("session service unavailable")
				return {
					data: parentAgent
						? [{ info: { role: "user", agent: parentAgent } }]
						: [],
				}
			},
		},
		config: {
			get: async () => ({
				data: {
					agent: {
						[targetAgent]: {
							permission: { edit: "allow", write: "allow", bash: "allow" },
						},
					},
				},
		}),
		},
		agents: async () => ({ data: [{ name: targetAgent, mode: "subagent" }] }),
	} as unknown as OpencodeClient
}

function createSessionTable(database: Database): void {
	database.exec(`
		CREATE TABLE sessions (
			id TEXT PRIMARY KEY,
			branch TEXT NOT NULL,
			path TEXT NOT NULL,
			created_at TEXT NOT NULL,
			launch_mode TEXT,
			profile TEXT,
			ocx_bin TEXT
		)
	`)
}

describe("worktree automation boundaries", () => {
	test("routes the managed-session guard through the real worktree_create tool", async () => {
		const home = await mkdtemp(path.join(os.tmpdir(), "opencode-worktree-home-"))
		const directory = await mkdtemp(path.join(os.tmpdir(), "opencode-worktree-project-"))
		const previousHome = process.env.HOME
		process.env.HOME = home

		try {
			const database = await initStateDb(directory)
			addSession(database, {
				id: "managed-child",
				branch: "feature/already-isolated",
				path: path.join(directory, "worktree"),
				createdAt: new Date().toISOString(),
			})

			const client = createClient()
			const plugin = await worktreePlugin({ directory, client } as never)
			const tool = plugin.tool?.worktree_create
			if (!tool) throw new Error("worktree_create tool is not registered")

			const result = await tool.execute(
				{ branch: "feature/nested" },
				{ sessionID: "managed-child" } as never,
			)

			expect(result).toContain("cannot run from a session already managed")
			expect(getSession(database, "managed-child")?.branch).toBe("feature/already-isolated")
		} finally {
			if (previousHome === undefined) delete process.env.HOME
			else process.env.HOME = previousHome
			await rm(home, { recursive: true, force: true })
			await rm(directory, { recursive: true, force: true })
		}
	})

	test("claims before launch and removes the claim when terminal launch fails", async () => {
		const database = new Database(":memory:")
		createSessionTable(database)
		const order: string[] = []

		const result = await worktreePlugin.testInternals.finalizeWorktreeLaunch({
			database,
			worktreePath: "/tmp/worktree",
			launchArgv: ["opencode", "--session", "child"],
			branch: "feature/child",
			forkedSessionId: "child",
			sessionRecord: {
				id: "child",
				branch: "feature/child",
				path: "/tmp/worktree",
				createdAt: new Date().toISOString(),
				launchMode: "plain",
				profile: null,
				ocxBin: null,
			},
			log: { debug() {}, info() {}, warn() {}, error() {} },
			openTerminalFn: async () => {
				order.push(`launch:${getSession(database, "child") ? "claimed" : "unclaimed"}`)
				return { success: false, error: "terminal unavailable" }
			},
			deleteForkedSessionFn: async () => {
				order.push("delete-session")
			},
			removeWorktreeFn: async () => {
				order.push("remove-worktree")
			},
		})

		expect(result.success).toBe(false)
		expect(order).toEqual(["launch:claimed", "delete-session", "remove-worktree"])
		expect(getSession(database, "child")).toBeNull()
		database.close()
	})

	test("does not launch when durable session registration fails", async () => {
		const database = new Database(":memory:")
		createSessionTable(database)
		addSession(database, {
			id: "duplicate-child",
			branch: "feature/existing",
			path: "/tmp/existing",
			createdAt: new Date().toISOString(),
		})
		let launchAttempted = false
		let forkedSessionDeleted = false
		let worktreeRemoved = false

		const result = await worktreePlugin.testInternals.finalizeWorktreeLaunch({
			database,
			worktreePath: "/tmp/new-worktree",
			launchArgv: ["opencode", "--session", "duplicate-child"],
			branch: "feature/new",
			forkedSessionId: "duplicate-child",
			sessionRecord: {
				id: "duplicate-child",
				branch: "feature/new",
				path: "/tmp/new-worktree",
				createdAt: new Date().toISOString(),
				launchMode: "plain",
				profile: null,
				ocxBin: null,
			},
			log: { debug() {}, info() {}, warn() {}, error() {} },
			openTerminalFn: async () => {
				launchAttempted = true
				return { success: true }
			},
			deleteForkedSessionFn: async () => {
				forkedSessionDeleted = true
			},
			removeWorktreeFn: async () => {
				worktreeRemoved = true
			},
		})

		expect(result.success).toBe(false)
		expect(result.error).toContain("Failed to register forked session")
		expect(launchAttempted).toBe(false)
		expect(forkedSessionDeleted).toBe(true)
		expect(worktreeRemoved).toBe(true)
		expect(getSession(database, "duplicate-child")?.branch).toBe("feature/existing")
		database.close()
	})

	test("reports every cleanup failure after a terminal launch failure", async () => {
		const database = new Database(":memory:")
		createSessionTable(database)
		const warnings: string[] = []

		const result = await worktreePlugin.testInternals.finalizeWorktreeLaunch({
			database,
			worktreePath: "/tmp/worktree",
			launchArgv: ["opencode", "--session", "child"],
			branch: "feature/child",
			forkedSessionId: "child",
			sessionRecord: {
				id: "child",
				branch: "feature/child",
				path: "/tmp/worktree",
				createdAt: new Date().toISOString(),
				launchMode: "plain",
				profile: null,
				ocxBin: null,
			},
			log: { debug() {}, info() {}, warn(message) { warnings.push(message) }, error() {} },
			openTerminalFn: async () => ({ success: false, error: "terminal unavailable" }),
			removeSessionFn: () => {
				throw new Error("database is read-only")
			},
			deleteForkedSessionFn: async () => {
				throw new Error("session service unavailable")
			},
			removeWorktreeFn: async () => {
				throw new Error("worktree is busy")
			},
		})

		expect(result.success).toBe(false)
		expect(result.error).toContain("terminal unavailable")
		expect(result.error).toContain("Failed to remove claimed session child: database is read-only")
		expect(result.error).toContain("Failed to delete forked session child: session service unavailable")
		expect(result.error).toContain("Failed to remove worktree after launch failure: worktree is busy")
		expect(warnings).toHaveLength(3)
		database.close()
	})

	test("cleans only the claimed child when another session shares its branch", async () => {
		const database = new Database(":memory:")
		createSessionTable(database)
		addSession(database, {
			id: "unrelated-session",
			branch: "feature/shared",
			path: "/tmp/unrelated",
			createdAt: new Date().toISOString(),
		})

		const result = await worktreePlugin.testInternals.finalizeWorktreeLaunch({
			database,
			worktreePath: "/tmp/child",
			launchArgv: ["opencode", "--session", "child"],
			branch: "feature/shared",
			forkedSessionId: "child",
			sessionRecord: {
				id: "child",
				branch: "feature/shared",
				path: "/tmp/child",
				createdAt: new Date().toISOString(),
				launchMode: "plain",
				profile: null,
				ocxBin: null,
			},
			log: { debug() {}, info() {}, warn() {}, error() {} },
			openTerminalFn: async () => ({ success: false, error: "terminal unavailable" }),
			deleteForkedSessionFn: async () => undefined,
		})

		expect(result.success).toBe(false)
		expect(getSession(database, "child")).toBeNull()
		expect(getSession(database, "unrelated-session")?.branch).toBe("feature/shared")
		database.close()
	})

	test("routes universal date awareness through the installed system transform hook", async () => {
		const directory = await mkdtemp(path.join(os.tmpdir(), "opencode-workspace-project-"))

		try {
			const plugin = await workspacePlugin({ directory, client: createClient() } as never)
			const hook = plugin["experimental.chat.system.transform"]
			if (!hook) throw new Error("system transform hook is not registered")

			const output = { system: [] as string[] }
			await hook({ sessionID: "session" } as never, output)

			expect(output.system).toHaveLength(1)
			expect(output.system[0]).toContain("<date-awareness>")
		} finally {
			await rm(directory, { recursive: true, force: true })
		}
	})

	test("loads routing, isolation, review, and delivery rules from scoped agent prompts", async () => {
		const prompts = await readAgentPromptsFromConfig()

		expect(prompts.plan).toContain("READ-ONLY planning orchestrator")
		expect(prompts.plan).toContain("`explore` only")
		expect(prompts.plan).toContain("`researcher` only")
		expect(prompts.plan).toContain("Planning, research, review, and casual chat do not create worktrees")
		expect(prompts.plan).toContain("hand off to the `build` orchestrator")

		expect(prompts.build).toContain("BUILD ORCHESTRATOR")
		expect(prompts.build).toContain("Delegate ALL code changes and verification to `coder`")
		expect(prompts.build).toContain("plan_read")
		expect(prompts.build).toContain("All implementation requires a dedicated non-default branch")
		expect(prompts.build).toContain("coder never commits or pushes")
		expect(prompts.build).toContain("Commit only when the user explicitly requests a commit")
		expect(prompts.build).toContain("Push only when explicitly requested; never force-push")
		expect(prompts.build).toContain("delegate `reviewer`")
		expect(prompts.build).not.toContain("delivery policy")
	})

	test("enforces the plan-to-build boundary in the runtime configuration", async () => {
		const config = parseJsonc(await Bun.file(configPath).text()) as OpenCodeConfig
		const taskPermission = config.agent?.plan?.permission?.task

		expect(taskPermission).toEqual({
			"*": "deny",
			"explore": "allow",
			"researcher": "allow",
			"reviewer": "allow",
			"build": "allow",
		})
		expect(
			backgroundAgentsPlugin.testInternals.isPlanDelegatingToWriteCapable("plan", false),
		).toBe(true)
		expect(
			backgroundAgentsPlugin.testInternals.isPlanDelegatingToWriteCapable("plan", true),
		).toBe(false)
	})

	test("blocks a plan session from reaching coder through the runtime task hook", async () => {
		const home = await mkdtemp(path.join(os.tmpdir(), "opencode-background-home-"))
		const directory = await mkdtemp(path.join(os.tmpdir(), "opencode-background-project-"))
		const previousHome = process.env.HOME
		process.env.HOME = home

		try {
			const client = {
				app: { log: async () => undefined },
				session: {
					messages: async () => ({ data: [{ info: { role: "user", agent: "plan" } }] }),
				},
			} as unknown as OpencodeClient
			const plugin = await backgroundAgentsPlugin({ directory, client } as never)
			const hook = plugin["tool.execute.before"]
			if (!hook) throw new Error("background task guard is not registered")

			await expect(
				hook(
					{ tool: "task", sessionID: "plan-session", callID: "call" },
					{ args: { subagent_type: "coder" } },
				),
			).rejects.toThrow("Planning sessions cannot delegate")
		} finally {
			if (previousHome === undefined) delete process.env.HOME
			else process.env.HOME = previousHome
			await rm(home, { recursive: true, force: true })
			await rm(directory, { recursive: true, force: true })
		}
	})

	test("blocks a default-worktree build session before it can reach a write-capable agent", async () => {
		const home = await mkdtemp(path.join(os.tmpdir(), "opencode-background-home-"))
		const { repository } = await createGitRepository("opencode-default")
		const previousHome = process.env.HOME
		process.env.HOME = home

		try {
			const plugin = await backgroundAgentsPlugin({
				directory: repository,
				client: createTaskClient("build", "coder"),
			} as never)
			const hook = plugin["tool.execute.before"]
			if (!hook) throw new Error("background task guard is not registered")

			await expect(
				hook(
					{ tool: "task", sessionID: "build-session", callID: "call" },
					{ args: { subagent_type: "coder" } },
				),
			).rejects.toThrow("managed, non-default worktree session")
		} finally {
			if (previousHome === undefined) delete process.env.HOME
			else process.env.HOME = previousHome
			await runCommand(["git", "worktree", "remove", "--force", `${repository}-worktree`], repository)
			await rm(repository, { recursive: true, force: true })
			await rm(home, { recursive: true, force: true })
		}
	})

	test("allows a managed non-default build session to reach a write-capable agent", async () => {
		const home = await mkdtemp(path.join(os.tmpdir(), "opencode-background-home-"))
		const { repository, worktree } = await createGitRepository("opencode-managed")
		const previousHome = process.env.HOME
		process.env.HOME = home

		try {
			const database = await initStateDb(worktree)
			addSession(database, {
				id: "build-session",
				branch: "feature/test",
				path: worktree,
				createdAt: new Date().toISOString(),
			})
			database.close()

			const plugin = await backgroundAgentsPlugin({
				directory: worktree,
				client: createTaskClient("build", "coder"),
			} as never)
			const hook = plugin["tool.execute.before"]
			if (!hook) throw new Error("background task guard is not registered")

			await hook(
				{ tool: "task", sessionID: "build-session", callID: "call" },
				{ args: { subagent_type: "coder" } },
			)
		} finally {
			if (previousHome === undefined) delete process.env.HOME
			else process.env.HOME = previousHome
			await runCommand(["git", "worktree", "remove", "--force", `${repository}-worktree`], repository)
			await rm(repository, { recursive: true, force: true })
			await rm(home, { recursive: true, force: true })
		}
	})

	test("blocks planning from native-tasking any write-capable target", async () => {
		const home = await mkdtemp(path.join(os.tmpdir(), "opencode-background-home-"))
		const directory = await mkdtemp(path.join(os.tmpdir(), "opencode-background-project-"))
		const previousHome = process.env.HOME
		process.env.HOME = home

		try {
			const plugin = await backgroundAgentsPlugin({
				directory,
				client: createTaskClient("plan", "scribe"),
			} as never)
			const hook = plugin["tool.execute.before"]
			if (!hook) throw new Error("background task guard is not registered")

			await expect(
				hook(
					{ tool: "task", sessionID: "plan-session", callID: "call" },
					{ args: { subagent_type: "scribe" } },
				),
			).rejects.toThrow("Planning sessions cannot delegate")
		} finally {
			if (previousHome === undefined) delete process.env.HOME
			else process.env.HOME = previousHome
			await rm(home, { recursive: true, force: true })
			await rm(directory, { recursive: true, force: true })
		}
	})

	test("fails closed when caller session identity lookup fails for a write-capable task", async () => {
		const home = await mkdtemp(path.join(os.tmpdir(), "opencode-background-home-"))
		const directory = await mkdtemp(path.join(os.tmpdir(), "opencode-background-project-"))
		const previousHome = process.env.HOME
		process.env.HOME = home

		try {
			const plugin = await backgroundAgentsPlugin({
				directory,
				client: createTaskClient("build", "coder", { lookupError: true }),
			} as never)
			const hook = plugin["tool.execute.before"]
			if (!hook) throw new Error("background task guard is not registered")

			await expect(
				hook(
					{ tool: "task", sessionID: "unknown-session", callID: "call" },
					{ args: { subagent_type: "coder" } },
				),
			).rejects.toThrow("caller session identity could not be resolved")
		} finally {
			if (previousHome === undefined) delete process.env.HOME
			else process.env.HOME = previousHome
			await rm(home, { recursive: true, force: true })
			await rm(directory, { recursive: true, force: true })
		}
	})
})
