import { afterEach, expect, test } from "bun:test";
import { mkdtemp, mkdir, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { canonical } from "../opencode/orchestrator/delegations";
import { assertWriteTargets } from "../opencode/orchestrator/write-targets";

const directories: string[] = [];
afterEach(async () => {
  for (const directory of directories.splice(0))
    await rm(directory, { recursive: true, force: true });
});
async function fixture() {
  const directory = await canonical(
    await mkdtemp(path.join(tmpdir(), "orchestrator-writes-")),
  );
  directories.push(directory);
  await mkdir(path.join(directory, "src"));
  await mkdir(path.join(directory, "outside"));
  return { directory, ownership: [path.join(directory, "src")] };
}
const patch = (body: string) => ({
  patchText: `*** Begin Patch\n${body}\n*** End Patch`,
});

test("native patches check every add, update, delete and move path before execution", async () => {
  const child = await fixture();
  await assertWriteTargets(
    "apply_patch",
    patch(
      "*** Add File: src/new.txt\n+new\n*** Update File: src/old.txt\n*** Move to: src/moved.txt\n@@\n-old\n+new\n*** Delete File: src/delete.txt",
    ),
    child,
  );
  for (const header of ["Add File", "Update File", "Delete File", "Move to"]) {
    await expect(
      assertWriteTargets(
        "apply_patch",
        patch(
          `*** Add File: src/new.txt\n+new\n*** ${header}: outside/file.txt`,
        ),
        child,
      ),
    ).rejects.toThrow("outside delegated");
  }
  for (const filename of [
    "src/../../escape.txt",
    "src-sibling/file.txt",
    path.join(child.directory, "outside/file.txt"),
  ]) {
    await expect(
      assertWriteTargets(
        "apply_patch",
        patch(`*** Add File: ${filename}\n+new`),
        child,
      ),
    ).rejects.toThrow("outside delegated");
  }
  await assertWriteTargets(
    "apply_patch",
    {
      patchText:
        "*** Begin Patch\r\n*** Add File: src/crlf.txt\r\n+new\r\n*** End Patch\r\n",
    },
    child,
  );
});

test("native edits reject symlink escapes including destinations that do not exist yet", async () => {
  const child = await fixture();
  await symlink("../outside", path.join(child.directory, "src/link"));
  await symlink(
    "../outside/new.txt",
    path.join(child.directory, "src/dangling"),
  );
  await symlink(
    "../outside/missing",
    path.join(child.directory, "src/dangling-dir"),
  );
  for (const filename of [
    "src/link/new.txt",
    "src/dangling",
    "src/dangling-dir/new.txt",
  ]) {
    await expect(
      assertWriteTargets("write", { filePath: filename }, child),
    ).rejects.toThrow("outside delegated");
    await expect(
      assertWriteTargets(
        "apply_patch",
        patch(`*** Add File: ${filename}\n+new`),
        child,
      ),
    ).rejects.toThrow("outside delegated");
  }
  await assertWriteTargets("edit", { filePath: "src/file.txt" }, child);
});

test("missing targets and shell-wrapped patches fail before native execution", async () => {
  const child = await fixture();
  for (const patchText of [
    undefined,
    "*** Begin Patch\n*** End Patch",
    "*** Begin Patch\n*** Add File: \n*** End Patch",
    "cat <<'EOF'\n*** Begin Patch\n*** Add File: src/a\n+a\n*** End Patch\nEOF",
  ]) {
    await expect(
      assertWriteTargets("apply_patch", { patchText }, child),
    ).rejects.toThrow();
  }
  await expect(assertWriteTargets("write", {}, child)).rejects.toThrow(
    "Cannot resolve",
  );
});
