import { execFile } from "node:child_process";
import { constants } from "node:fs";
import { lstat, mkdir, open, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

const exec = promisify(execFile);
const marker =
  "# OpenCode delegation artifacts; preserve evidence until explicitly retired.\n*\n";

async function git(directory: string, ...args: string[]) {
  const env: NodeJS.ProcessEnv = { ...process.env, GIT_NO_LAZY_FETCH: "1" };
  for (const name of [
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
  ])
    delete env[name];
  return exec(
    "git",
    ["--no-optional-locks", "-c", "core.fsmonitor=false", ...args],
    {
      cwd: directory,
      env,
      timeout: 10_000,
      maxBuffer: 1024 * 1024,
    },
  );
}

export async function artifactPath(directory: string, id: string) {
  try {
    const result = await git(directory, "rev-parse", "--is-inside-work-tree");
    if (result.stdout.trim() !== "true") return undefined;
  } catch (error) {
    if ((error as { code?: unknown }).code === 128) return undefined;
    throw error;
  }
  return path.join(directory, ".opencode-artifacts", id);
}

/** Runs only after the coder's reservation is saved, before its first prompt. */
export async function prepareArtifacts(directory: string, target: string) {
  for (const folder of [path.dirname(target), target]) {
    try {
      await mkdir(folder);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
    }
    if (!(await lstat(folder)).isDirectory())
      throw new Error(
        "Artifact storage must be a real directory inside the delegation directory, not a symlink.",
      );
  }
  // An ignore must never hide existing tracked content. Each delegation gets its
  // own ignore, so unrelated files in the parent directory remain visible to Git.
  const tracked = await git(directory, "ls-files", "-z", "--", target);
  if (tracked.stdout)
    throw new Error(
      "Artifact storage contains tracked files; preserve them and choose a fresh delegation.",
    );
  const filename = path.join(target, ".gitignore");
  const entries = await readdir(target);
  if (entries.length && !entries.includes(".gitignore"))
    throw new Error(
      "Artifact storage has existing files without its managed marker; preserve them and repair the directory explicitly.",
    );
  try {
    const file = await open(
      filename,
      constants.O_WRONLY |
        constants.O_CREAT |
        constants.O_EXCL |
        constants.O_NOFOLLOW,
      0o600,
    );
    try {
      await file.writeFile(marker);
    } finally {
      await file.close();
    }
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
    if (
      !(await lstat(filename)).isFile() ||
      (await readFile(filename, "utf8")) !== marker
    )
      throw new Error(
        "Artifact ignore differs from the managed marker; preserve it and repair the artifact directory explicitly.",
      );
  }
  await git(
    directory,
    "check-ignore",
    "--quiet",
    "--",
    path.join(target, "probe"),
  );
}
