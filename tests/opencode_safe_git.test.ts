import { expect, test } from "bun:test";
import {
  safeGitArgv,
  safeGitEnv,
  safeGitFlags,
  safeGitPrefixLength,
} from "../opencode/orchestrator/safe-git";

test("a safe invocation carries the global flags before the caller's command", () => {
  expect(safeGitArgv(["rev-parse", "HEAD"])).toEqual([
    ...safeGitFlags,
    "rev-parse",
    "HEAD",
  ]);
});

test("a safe environment drops an inherited repository and refuses a lazy fetch", () => {
  const env = safeGitEnv({
    GIT_DIR: "/elsewhere/.git",
    GIT_WORK_TREE: "/elsewhere",
    GIT_INDEX_FILE: "/elsewhere/.git/index",
    GIT_COMMON_DIR: "/elsewhere/.git",
    PATH: "/usr/bin",
  });

  expect(env.GIT_DIR).toBeUndefined();
  expect(env.GIT_WORK_TREE).toBeUndefined();
  expect(env.GIT_INDEX_FILE).toBeUndefined();
  expect(env.GIT_COMMON_DIR).toBeUndefined();
  expect(env.GIT_NO_LAZY_FETCH).toBe("1");
  expect(env.PATH).toBe("/usr/bin");
});

// The property the permission normalizer depends on, stated here rather than
// at one of the four call sites: normalizing an already-normalized command has
// to produce the same command, and it does exactly when what the prefix adds
// is what the recogniser consumes.
test("the recogniser consumes exactly what a safe invocation adds", () => {
  const argv = safeGitArgv(["status", "--porcelain"]);

  let index = 0;
  let consumed = safeGitPrefixLength(argv, index);
  while (consumed) {
    index += consumed;
    consumed = safeGitPrefixLength(argv, index);
  }
  expect(argv.slice(index)).toEqual(["status", "--porcelain"]);
});

test("a configuration the module does not supply is not consumed", () => {
  // Left for the caller to refuse. Consuming it here would silently strip a
  // -c the caller must reject, which is the opposite of what it is for.
  expect(safeGitPrefixLength(["-c", "core.pager=less"], 0)).toBe(0);
  expect(safeGitPrefixLength(["-c"], 0)).toBe(0);
  expect(safeGitPrefixLength(["-C", "/tmp"], 0)).toBe(0);
  expect(safeGitPrefixLength(["status"], 0)).toBe(0);
  expect(safeGitPrefixLength([], 0)).toBe(0);
});
