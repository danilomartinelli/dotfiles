// Reading a space's checkout from Git, with no view state.
import { exec } from "herdr";

const basename = (path) => path.replace(/\/+$/, "").split("/").pop();

// A Git read that hangs (a lock, a slow mount) must not hold up the whole list.
const GIT_TIMEOUT_MS = 10000;

// The first terminal defines a space's checkout, not whichever pane is focused.
// Pass a panes() snapshot: each API call copies the full pane list.
export function spaceFolder(space, paneList) {
  const tabIDs = new Set((space.tabs ?? []).map((tab) => tab.id));
  return paneList.find((pane) => tabIDs.has(pane.tab) && pane.cwd)?.cwd || space.folder;
}

export const checkoutKey = (space, paneList) =>
  JSON.stringify([space.machine ?? null, spaceFolder(space, paneList)]);

// Both runs, finished: a read isn't done while one of its pair still holds a slot.
async function both(a, b) {
  const done = await Promise.allSettled([a, b]);
  const failed = done.find((d) => d.status === "rejected");
  if (failed) throw failed.reason;
  return done.map((d) => d.value);
}

// Branch, ahead/behind and repository, or null if this isn't a repository.
// Throws when Git couldn't be asked, so the caller keeps what it knew.
// Ref-only reads: they don't scan the worktree and don't wake the index watch.
export async function readCheckout(cwd, on) {
  const git = (args) => exec("git", args, { cwd, on, timeout: GIT_TIMEOUT_MS });
  const [top, common] = await both(
    git(["rev-parse", "--path-format=absolute", "--show-toplevel"]),
    git(["rev-parse", "--path-format=absolute", "--git-common-dir"]),
  );
  if (top.code !== 0 || common.code !== 0) {
    // Only Git's own "no" is remembered as no repo; anything else is asked again.
    const stderr = top.code !== 0 ? top.stderr : common.stderr;
    if (!/not a git repository/i.test(stderr ?? "")) throw new Error("Cannot read repository metadata");
    return null;
  }

  const [branch, counts] = await both(
    git(["symbolic-ref", "-q", "HEAD"]),
    git(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"]),
  );
  // The repo's own .git folder names it; a worktree's top differs from it.
  const root = top.stdout.replace(/\n$/, "");
  const repo = common.stdout.replace(/\n$/, "");
  const info = {
    name: repo.endsWith("/.git") ? basename(repo.slice(0, -5)) : basename(repo).replace(/\.git$/, ""),
    branch: branch.code === 0 ? branch.stdout.trim().replace(/^refs\/heads\//, "") : "(detached)",
    ahead: 0,
    behind: 0,
    repo: JSON.stringify([on, repo]),
    linked: repo !== `${root}/.git`,
  };
  if (counts.code === 0) {
    const [ahead, behind] = counts.stdout.trim().split(/\s+/).map(Number);
    info.ahead = ahead || 0;
    info.behind = behind || 0;
  }
  return info;
}
