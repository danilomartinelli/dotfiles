import type { Plugin } from "@opencode-ai/plugin";
import { assertNoProjectDcpOverride } from "./internal/dcp-policy";

const DcpPlugin: Plugin = async (input) => {
	const managedConfigDirectory = process.env.OPENCODE_CONFIG_DIR;
	if (!managedConfigDirectory) {
		throw new Error("OPENCODE_CONFIG_DIR is required for managed DCP policy");
	}
	await assertNoProjectDcpOverride(input.directory, managedConfigDirectory);

	const { default: createDcpPlugin } = await import("@tarquinen/opencode-dcp");
	return (createDcpPlugin as Plugin)(input);
};

export default DcpPlugin;
