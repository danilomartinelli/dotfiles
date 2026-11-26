// Address a single branch explicitly, including when a topic branch tracks origin/main.
export async function readPushTarget(git) {
  const head = await git(["symbolic-ref", "--quiet", "--short", "HEAD"]);
  if (head.code !== 0) return null;
  const branch = head.stdout.trim();
  const ref = `refs/heads/${branch}`;
  const [refs, remotes] = await Promise.all([
    git(["for-each-ref", "--format=%(refname)%00%(push:remotename)%00%(upstream:remotename)", ref]),
    git(["remote"]),
  ]);
  if (refs.code || remotes.code) return null;
  const names = remotes.stdout.trim().split("\n").filter(Boolean);
  const line = refs.stdout.split("\n").find((row) => row.startsWith(ref + "\0"));
  const [, pushRemote, upstream] = (line ?? "").split("\0");
  const remote = pushRemote || upstream || (names.includes("origin") ? "origin" : names.length === 1 && names[0]);
  if (!names.includes(remote)) return null;
  const target = { branch, remote, setUpstream: !upstream, pending: false };
  if (!line) return target; // Unborn branch. Commit & Push can publish its first commit.
  const tracking = `refs/remotes/${remote}/${branch}`;
  const exists = await git(["show-ref", "--verify", "--quiet", tracking]);
  if (exists.code === 1) target.pending = true;
  else if (exists.code === 0) {
    const ahead = await git(["rev-list", "--count", `${tracking}..${ref}`]);
    target.pending = ahead.code === 0 && Number(ahead.stdout) > 0;
  }
  return target;
}

export async function pushBranch(git, target) {
  const current = await readPushTarget(git);
  if (!current || current.branch !== target.branch || current.remote !== target.remote)
    throw Error("The branch or push remote changed. Refresh and try again.");
  const ref = `refs/heads/${current.branch}`;
  const result = await git(["-c", `remote.${current.remote}.mirror=false`, "push", "--no-follow-tags",
    ...(current.setUpstream ? ["--set-upstream"] : []), "--", current.remote, `${ref}:${ref}`]);
  if (result.code !== 0) throw Error((result.stderr || result.stdout).trim() || "Git rejected the push.");
}
