// Reading from Git, with no view state: each function takes a `git(args)` runner
// and returns plain data. Nothing here fetches, so it all reads the last fetch.
import { changedFiles, parseLog, commitFiles, githubRepo } from "./model.js";

const NO_HELPERS = ["--no-renames", "--no-ext-diff", "--no-textconv"];
const LOG_FORMAT = "--format=%H%x00%h%x00%an%x00%ae%x00%at%x00%s%x00%b%x1e";

const lines = (text) => text.split("\n").filter(Boolean);

export async function readStatus(git) {
  const status = await git([
    "status",
    "--porcelain=v1",
    "-z",
    "--no-renames",
    "--untracked-files=all",
  ]);
  if (status.code !== 0) throw Error(status.stderr || "Cannot read changes");

  const staged = await git(["diff", "--cached", "--numstat", "-z", ...NO_HELPERS]);
  const unstaged = await git(["diff", "--numstat", "-z", ...NO_HELPERS]);
  if (staged.code !== 0) throw Error(staged.stderr || "Cannot read change statistics");
  if (unstaged.code !== 0) throw Error(unstaged.stderr || "Cannot read change statistics");

  const head = await git(["rev-parse", "--verify", "HEAD"]);
  return {
    files: changedFiles(status.stdout, [staged.stdout, unstaged.stdout]),
    hasHead: head.code === 0,
  };
}

// The current branch, and "owner/repo" when origin is on GitHub.
export async function readBranchAndRepo(git) {
  const branch = await git(["rev-parse", "--abbrev-ref", "HEAD"]);
  // shortcut: only GitHub remotes get a commit link, upgrade when another host is needed.
  const origin = await git(["remote", "get-url", "origin"]);
  return {
    branch: branch.code === 0 ? branch.stdout.trim() : null,
    repo: origin.code === 0 ? githubRepo(origin.stdout) : null,
  };
}

// What to compare HEAD with: its upstream, or on a branch never pushed, the
// remote's default branch. Null with neither.
// shortcut: a branch pushed without an upstream compares with the default branch, upgrade by also trying <remote>/<branch>.
async function comparisonRef(git) {
  const upstream = await git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]);
  if (upstream.code === 0) return { ref: "@{u}", name: upstream.stdout.trim() };

  const ref = "refs/remotes/origin/HEAD";
  const defaultBranch = await git(["symbolic-ref", "--short", ref]);
  if (defaultBranch.code === 0 && defaultBranch.stdout.trim()) {
    return { ref, name: defaultBranch.stdout.trim() };
  }
  return null;
}

// The files and commits HEAD has over that ref. `previous` is the last result:
// this runs with every status poll, and only a new commit or fetch can change it.
export async function readCommitted(git, previous, fileLimit) {
  try {
    const against = await comparisonRef(git);
    if (!against) return null;

    const base = await git(["merge-base", "HEAD", against.ref]);
    const head = await git(["rev-parse", "--verify", "HEAD"]);
    if (base.code !== 0 || head.code !== 0) return null;
    const from = base.stdout.trim();
    const key = `${from}:${head.stdout.trim()}`;
    if (previous?.key === key) return previous;

    const numstat = await git(["diff", ...NO_HELPERS, "--numstat", "-z", from, "HEAD"]);
    const names = await git(["diff", ...NO_HELPERS, "--name-status", "-z", from, "HEAD"]);
    const commits = await git(["rev-list", `${from}..HEAD`]);
    if (numstat.code !== 0 || names.code !== 0 || commits.code !== 0) return null;

    const files = commitFiles(numstat.stdout, names.stdout);
    return {
      key,
      base: from,
      ref: against.ref,
      name: against.name,
      total: files.length,
      files: files.slice(0, fileLimit),
      unpushed: new Set(lines(commits.stdout)),
    };
  } catch {
    return null;
  }
}

// The remote's default branch: its name, how far behind it we are, and which
// commits it lacks. Null when the clone never recorded one.
export async function readRemoteHead(git, committed) {
  const remote = committed?.name.split("/")[0] ?? "origin";
  const ref = `refs/remotes/${remote}/HEAD`;
  const target = await git(["symbolic-ref", "--short", ref]);
  if (target.code !== 0 || !target.stdout.trim()) return null;

  const base = await git(["merge-base", "HEAD", ref]);
  if (base.code !== 0) return null;
  const behind = await git(["rev-list", "--count", `HEAD..${ref}`]);
  const ahead = await git(["rev-list", `${base.stdout.trim()}..HEAD`]);
  if (behind.code !== 0 || ahead.code !== 0) return null;

  return {
    name: `${remote}/HEAD`,
    target: target.stdout.trim(),
    behind: Number(behind.stdout) || 0,
    ahead: new Set(lines(ahead.stdout)),
  };
}

// How many commits the compared ref has that HEAD lacks.
export async function readBehind(git, committed) {
  if (!committed) return 0;
  const behind = await git(["rev-list", "--count", `HEAD..${committed.ref}`]);
  return behind.code === 0 ? Number(behind.stdout) || 0 : 0;
}

export async function readLog(git, count, skip) {
  const log = await git([
    "log",
    "--no-color",
    LOG_FORMAT,
    "-n",
    String(count),
    "--skip",
    String(skip),
  ]);
  if (log.code !== 0) throw Error(log.stderr || "Cannot read history");
  return parseLog(log.stdout);
}

export async function readCommitFiles(git, hash) {
  // Together, --numstat and --name-status print only the last, so ask twice.
  const show = (flag) =>
    git(["show", "--diff-merges=first-parent", "--format=", ...NO_HELPERS, flag, "-z", hash]);
  const numstat = await show("--numstat");
  const names = await show("--name-status");
  if (numstat.code !== 0 || names.code !== 0) {
    throw Error(numstat.stderr || names.stderr || "Cannot read commit");
  }
  return commitFiles(numstat.stdout, names.stdout);
}
