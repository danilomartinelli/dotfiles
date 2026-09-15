/**
 * The paths a native patch says it will touch.
 *
 * This is an adapter over a grammar the native apply_patch tool owns, which is
 * why it stays its own module: the header spellings can change under us, and
 * nothing else here has to care when they do. Core still validates and applies
 * the hunks; this only answers which files a delegation is about to write.
 */
export function patchTargets(patchText: unknown): string[] {
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
