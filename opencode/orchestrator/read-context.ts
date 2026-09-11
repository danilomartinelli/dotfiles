import { stat } from "node:fs/promises";
import path from "node:path";

export function directoryContext(directory: string): string {
  return `Session directory: ${directory}. Resolve relative paths here. After a missing path, rediscover files here with glob/grep; never reconstruct worktree paths from project IDs or reuse paths from another session.`;
}

/** Preserve the requested target; a missing path is guidance, never a remapping. */
export async function prepareRead(
  tool: string,
  args: Record<string, unknown>,
  directory: string,
) {
  const field =
    tool === "read" || tool === "lsp"
      ? "filePath"
      : ["glob", "grep", "list"].includes(tool)
        ? "path"
        : undefined;
  if (!field) return;
  const requested = args[field] ?? (field === "path" ? "." : undefined);
  if (typeof requested !== "string") return;
  const target = path.resolve(directory, requested);
  try {
    await stat(target);
  } catch (error) {
    if (
      !["ENOENT", "ENOTDIR"].includes(
        (error as NodeJS.ErrnoException).code ?? "",
      )
    )
      throw error;
    throw new Error(
      `Read target does not exist: ${target}. ${directoryContext(directory)} If the session directory itself is gone, ask the root to select an existing checkout.`,
    );
  }
  args[field] = target;
}
