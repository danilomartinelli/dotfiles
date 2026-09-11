import { expect, test } from "bun:test";
import { mkdtemp, mkdir, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { prepareRead } from "../opencode/orchestrator/read-context";

test("file queries anchor relative paths and recover missing worktrees without redirecting files", async () => {
  const fixture = await mkdtemp(path.join(tmpdir(), "opencode-read-context-"));
  try {
    const directory = path.join(await realpath(fixture), "checkout");
    const other = path.join(await realpath(fixture), "other-checkout");
    await mkdir(directory);
    await mkdir(other);
    await writeFile(path.join(directory, "README.md"), "Current checkout.");
    await writeFile(path.join(other, "README.md"), "Other checkout.");
    const read = { filePath: "README.md" };
    await prepareRead("read", read, directory);
    expect(read.filePath).toBe(path.join(directory, "README.md"));
    const lsp = { filePath: "README.md", operation: "hover" };
    await prepareRead("lsp", lsp, directory);
    expect(lsp.filePath).toBe(read.filePath);
    for (const tool of ["glob", "grep", "list"]) {
      const args: Record<string, unknown> = { pattern: "README*" };
      await prepareRead(tool, args, directory);
      expect(args.path).toBe(directory);
    }
    const stale = {
      filePath: path.join(fixture, "missing-worktree/README.md"),
    };
    const original = { ...stale };
    await expect(prepareRead("read", stale, directory)).rejects.toThrow(
      `Session directory: ${directory}`,
    );
    expect(stale).toEqual(original);
    const explicit = { filePath: path.join(other, "README.md") };
    await prepareRead("read", explicit, directory);
    // Native external_directory permissions still decide access to this target.
    expect(explicit.filePath).toBe(path.join(other, "README.md"));
    await expect(
      prepareRead("grep", { path: "missing" }, directory),
    ).rejects.toThrow("rediscover files here");
    await rm(directory, { recursive: true });
    await expect(prepareRead("glob", {}, directory)).rejects.toThrow(
      "select an existing checkout",
    );
  } finally {
    await rm(fixture, { recursive: true, force: true });
  }
});
