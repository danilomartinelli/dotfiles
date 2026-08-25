import type { Plugin } from "@opencode-ai/plugin";

const GENERIC_MCP_RESOURCE_TOOLS = [
	"list_mcp_resources",
	"list_mcp_resource_templates",
	"read_mcp_resource",
] as const;

/**
 * Removes generic MCP resource probes from every user turn before OpenCode
 * resolves the callable catalog. Structured MCP tools remain governed by the
 * role permissions in opencode.jsonc.
 *
 * OpenCode maps generic resource tools to the broad `read` permission. A
 * file-reading agent therefore cannot hide those tools with a name-specific
 * permission rule. The per-message `tools` map is the runtime-supported seam
 * that hides them without weakening local read access.
 */
const RuntimeGuardPlugin: Plugin = async () => ({
	"chat.message": async (_input, output) => {
		const tools = { ...(output.message.tools ?? {}) };
		for (const toolName of GENERIC_MCP_RESOURCE_TOOLS) {
			tools[toolName] = false;
		}
		output.message.tools = tools;
	},
});

export default RuntimeGuardPlugin;
