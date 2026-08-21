import * as fs from "node:fs/promises";
import * as path from "node:path";

async function nearestOpenCodeDirectory(
	directory: string,
): Promise<string | null> {
	let cursor = path.resolve(directory);
	while (true) {
		const candidate = path.join(cursor, ".opencode");
		if (await fs.lstat(candidate).catch(() => null)) return candidate;
		const parent = path.dirname(cursor);
		if (parent === cursor) return null;
		cursor = parent;
	}
}

export async function assertNoProjectDcpOverride(
	directory: string,
	managedConfigDirectory: string,
): Promise<void> {
	const candidateDirectory = await nearestOpenCodeDirectory(directory);
	if (!candidateDirectory) return;

	const [candidateRealPath, managedRealPath] = await Promise.all([
		fs
			.realpath(candidateDirectory)
			.catch(() => path.resolve(candidateDirectory)),
		fs
			.realpath(managedConfigDirectory)
			.catch(() => path.resolve(managedConfigDirectory)),
	]);
	if (candidateRealPath === managedRealPath) return;

	for (const filename of ["dcp.jsonc", "dcp.json"]) {
		const candidate = path.join(candidateDirectory, filename);
		if (await fs.lstat(candidate).catch(() => null)) {
			throw new Error(
				`Repository DCP overrides are disabled; remove or archive ${candidate}`,
			);
		}
	}
}
