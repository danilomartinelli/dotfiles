/**
 * What makes a git invocation safe to run inside someone's checkout.
 *
 * Four places needed this and each carried its own answer: `--no-pager` in two
 * of them, `GIT_INDEX_FILE` scrubbed in two of them, `GIT_NO_LAZY_FETCH` set in
 * two of them, and the permission normalizer recognising the prefix by spelling
 * `core.fsmonitor=false` a second time. The rules are the same everywhere, so
 * they live here; launching the process is not, and stays with each caller,
 * because one of the four never launches anything.
 */

/**
 * Never paginate, never take the index lock, never start the fsmonitor daemon.
 * The daemon is the one that matters: it dies with the worktree it watched and
 * leaves every later command in that checkout reporting an IPC error.
 */
export const safeGitFlags = [
  "--no-pager",
  "--no-optional-locks",
  "-c",
  "core.fsmonitor=false",
] as const;

/**
 * Inherited pointers at another repository's internals. A plugin runs inside
 * whatever process started OpenCode, so any of these may already be set to a
 * checkout that has nothing to do with the directory being inspected.
 */
const inheritedRepository = [
  "GIT_DIR",
  "GIT_WORK_TREE",
  "GIT_INDEX_FILE",
  "GIT_COMMON_DIR",
];

/** The safe global flags, then the caller's own command. */
export function safeGitArgv(args: readonly string[]): string[] {
  return [...safeGitFlags, ...args];
}

/**
 * The environment a safe invocation runs in: no inherited repository, and no
 * lazy fetch, so inspecting a partial clone stays local and offline.
 */
export function safeGitEnv(
  base: NodeJS.ProcessEnv = process.env,
): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = { ...base, GIT_NO_LAZY_FETCH: "1" };
  for (const name of inheritedRepository) delete env[name];
  return env;
}

/**
 * How many tokens at `index` are a global flag this module already supplies, or
 * 0 for anything else. A normalizer drops what it is about to re-add, which is
 * what makes normalizing an already-normalized command produce the same
 * command; deciding that here is what keeps the two spellings of the prefix
 * from drifting apart.
 */
export function safeGitPrefixLength(
  argv: readonly string[],
  index: number,
): number {
  const flag = argv[index];
  if (flag === undefined) return 0;

  for (let position = 0; position < safeGitFlags.length; position++) {
    const safe = safeGitFlags[position];
    if (safe !== flag) continue;
    // A flag that takes a value is stored followed by it, so consuming the pair
    // means matching the value too.
    const value = safeGitFlags[position + 1];
    if (safe.startsWith("--")) return 1;
    if (value !== undefined && argv[index + 1] === value) return 2;
  }
  return 0;
}
