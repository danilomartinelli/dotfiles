import path from "node:path";
import { canonical } from "./delegations";

export const writeTools = new Set(["edit", "write", "apply_patch"]);

/** Match native patch path headers; core still validates and applies the hunks. */
function patchTargets(patchText: unknown): string[] {
  if (typeof patchText !== "string")
    throw new Error("Cannot resolve patch targets: patchText is required.");
  const lines = patchText.trim().split("\n");
  if (
    lines[0]?.trim() !== "*** Begin Patch" ||
    lines.at(-1)?.trim() !== "*** End Patch"
  )
    throw new Error("Supply a plain Begin/End patch without a shell wrapper.");
  const targets: string[] = [];
  for (const line of lines.slice(1, -1)) {
    const header = line.match(
      /^\*\*\* (?:Add File|Update File|Delete File|Move to):([\s\S]*)$/,
    );
    if (!header) continue;
    const filename = header[1].trim();
    if (!filename || filename.includes("\0"))
      throw new Error("Cannot resolve an empty or invalid patch target.");
    targets.push(filename);
  }
  if (!targets.length) throw new Error("Cannot resolve patch targets.");
  return targets;
}

export async function assertWriteTargets(
  tool: string,
  args: Record<string, unknown>,
  child: { directory: string; ownership: string[] },
) {
  const targets =
    tool === "apply_patch" ? patchTargets(args.patchText) : [args.filePath];
  for (const filename of targets) {
    if (typeof filename !== "string" || !filename)
      throw new Error("Cannot resolve write target.");
    const target = await canonical(path.resolve(child.directory, filename));
    if (
      !child.ownership.some(
        (owner) => target === owner || target.startsWith(`${owner}${path.sep}`),
      )
    )
      throw new Error("Write target is outside delegated file ownership.");
  }
}
