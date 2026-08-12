import { type Plugin, tool } from "@opencode-ai/plugin"

const repositoryPolicy = `Repository harness policy: OMO Slim remains the orchestration layer. Use configured repository skills before generic advice. Relevant sources are _shared/agents/skills (shared PM skills), .agents/skills (Matt Pocock engineering skills), and local .opencode/skills when present. Follow the repository instruction contract. Do not edit skills unless explicitly requested.`

const inventory = {
	name: "repository_skill_inventory",
	description:
		"Descriptive inventory of repository skill source roots and representative workflows; it does not execute skills.",
	sources: [
			{
				root: "_shared/agents/skills",
				role: "shared PM skills",
				examples: ["prd-development", "user-story", "roadmap-planning"],
			},
			{
				root: ".agents/skills",
				role: "Matt Pocock engineering skills",
				examples: ["code-review", "tdd", "triage", "grill-with-docs"],
			},
			{
				root: ".opencode/skills",
				role: "local skills (if present)",
				examples: [],
			},
		],
		behavior: "Descriptive only; this tool does not execute skills.",
}

const RepositoryHarness: Plugin = async () => ({
	"experimental.chat.system.transform": async (_input: unknown, output: { system: string[] }) => {
		output.system.push(repositoryPolicy)
	},
	tool: {
		repository_skill_inventory: tool({
			description: inventory.description,
			args: {},
			execute: async () => JSON.stringify(inventory),
		}),
	},
})

export default RepositoryHarness
