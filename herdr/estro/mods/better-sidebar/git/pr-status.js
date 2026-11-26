// Read-only PR discovery for each [machine, checkout]. This observer is separate
// from space rendering so frequent redraws never launch Git or GitHub commands.
import { exec, shared } from "herdr";

export const PR_POLL_MS = 60000;
const OPEN_PR_POLL_MS = 15000;
const MAX_LOOKUPS = 4;
export const prPlaceKey = (machine, folder) => JSON.stringify([machine ?? null, folder]);
const PR_FIELDS =
  "id,number,title,url,state,isDraft,headRefName,headRepository,updatedAt,statusCheckRollup,reviewDecision,mergeStateStatus";

/** Terminal PR states win over draft/CI flags left over from when it was open. */
export function prAppearance(pr, colors) {
  if (pr.state === "MERGED") return { icon: "merged", color: colors.ansi5, label: "Merged" };
  if (pr.state === "CLOSED") return { icon: "closed", color: colors.ansi1, label: "Closed" };
  if (pr.isDraft) return { icon: "draft", color: colors.dim, label: "Draft" };
  const checks = (pr.statusCheckRollup ?? []).map((check) =>
    String(check.conclusion || check.state || check.status).toUpperCase(),
  );
  const open = (color, label, ready = false) => ({ icon: "pull-request", color, label, ready });
  if (pr.mergeStateStatus === "DIRTY") return open(colors.ansi1, "Conflicts");
  if (checks.some((state) => ["FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"].includes(state)))
    return open(colors.ansi1, "Checks failed");
  if (pr.reviewDecision === "CHANGES_REQUESTED") return open(colors.ansi3, "Changes requested");
  if (checks.some((state) => ["EXPECTED", "PENDING", "QUEUED", "IN_PROGRESS", "REQUESTED", "WAITING"].includes(state)))
    return open(colors.ansi3, "Checks pending");
  // CLEAN is GitHub's own "mergeable now": an empty decision means no review is required.
  if (pr.mergeStateStatus === "CLEAN" && (pr.reviewDecision === "APPROVED" || !pr.reviewDecision))
    return open(colors.ansi2, "Ready to merge", true);
  return open(colors.ansi2, "Open");
}

/** Only github.com remotes are supported. Never pass an arbitrary remote URL to gh. */
export function githubRepository(url) {
  return /^(?:https?:\/\/github\.com\/|git@github\.com:|ssh:\/\/git@github\.com\/)([\w.-]+\/[\w.-]+?)(?:\.git)?\/?$/.exec(
    url.trim(),
  )?.[1];
}

/**
 * One observer per sidebar. Git runs on the checkout's machine; gh runs locally,
 * using the person's existing authentication. No helper executable is required.
 * Maps include the machine in their keys so remote paths cannot collide.
 */
export class PRStatusObserver {
  constructor() {
    this.places = new Map(); // Current checkout snapshots, replaced on refresh.
    this.checked = new Map(); // Checkout key -> last attempt time and branch.
    this.entries = new Map(); // Checkout key -> last published PRs or error.
    this.reading = new Set(); // At most one lookup per checkout.
  }

  refresh(places, cx) {
    this.places = new Map(
      places
        .filter((place) => place.folder)
        .map((place) => [prPlaceKey(place.machine, place.folder), place]),
    );
    for (const key of this.entries.keys()) if (!this.places.has(key)) this.entries.delete(key);
    for (const key of this.checked.keys()) if (!this.places.has(key)) this.checked.delete(key);
    const queries = new Map(); // Share identical gh calls only within this batch.
    for (const [key, place] of this.places) {
      if (this.reading.size >= MAX_LOOKUPS) break;
      if (this.reading.has(key)) continue;
      const prs = this.entries.get(key)?.prs ?? [];
      const interval = prs.some((pr) => pr.state === "OPEN") ? OPEN_PR_POLL_MS : PR_POLL_MS;
      const revision = prs.reduce((sum, pr) =>
        sum + (shared(`branch-pr.changed:${pr.repository.toLowerCase()}#${pr.number}`) ?? 0), 0);
      const last = this.checked.get(key);
      if (last && last.branch === place.branch && last.revision === revision &&
          Date.now() - last.at < interval) continue;

      this.reading.add(key);
      cx.spawn(async (cx) => {
        try {
          const prs = await this.lookup(place, queries);
          if (this.isCurrent(key, place))
            this.entries.set(key, { prs, branch: place.branch, updated: Date.now() });
        } catch (error) {
          if (this.isCurrent(key, place)) {
            const previous = this.entries.get(key);
            this.entries.set(key, {
              prs: previous?.branch === place.branch ? previous.prs : [],
              branch: place.branch,
              error: error.message,
              updated: previous?.updated,
            });
          }
        } finally {
          this.reading.delete(key);
          // Record the revision from before the read. A merge during the
          // request must trigger another lookup even if the old answer arrives last.
          if (this.isCurrent(key, place))
            this.checked.set(key, { at: Date.now(), branch: place.branch, revision });
          cx.notify();
        }
      });
    }
  }

  // A lookup may finish after navigation or a branch switch. Publish only if
  // the caller's checkout snapshot still describes a tracked space.
  isCurrent(key, place) {
    return this.places.has(key) && this.places.get(key).branch === place.branch;
  }

  async lookup(place, queries) {
    const git = (args) =>
      exec("git", ["--no-optional-locks", ...args], { cwd: place.folder, on: place.machine, timeout: 10000 });
    const head = await git(["symbolic-ref", "--quiet", "--short", "HEAD"]);
    if (head.code !== 0) {
      if (head.code === 1 || /not a git repository/i.test(head.stderr ?? "")) return [];
      throw new Error("Cannot read checkout branch");
    }
    const branch = head.stdout.trim();
    // Explicit worktree bindings survive local branch renames and take
    // precedence over guessing a PR from matching head branch names.
    const association = await git(["config", "--get", `branch.${branch}.herdr-pr`]);
    if (association.code !== 0 && association.code !== 1)
      throw new Error("Cannot read PR association");
    const binding = /^([\w.-]+\/[\w.-]+)#([1-9][0-9]*)$/.exec(association.stdout?.trim() ?? "");
    if (binding) {
      const pr = await this.query(queries, [
        "pr",
        "view",
        binding[2],
        "--repo",
        binding[1],
        "--json",
        PR_FIELDS,
      ]);
      return [{ ...pr, repository: binding[1] }];
    }

    const remotes = await git(["remote"]);
    if (remotes.code !== 0) throw new Error("Cannot read Git remotes");
    const repositories = new Set();
    for (const name of remotes.stdout.trim().split(/\r?\n/).filter(Boolean)) {
      const result = await git(["remote", "get-url", name]);
      if (result.code !== 0) throw new Error("Cannot read Git remote URL");
      const repository = githubRepository(result.stdout);
      if (repository) repositories.add(repository);
    }

    const candidates = [];
    const knownHeads = new Set([...repositories].map((repo) => repo.toLowerCase()));
    for (const repository of repositories) {
      const found = await this.query(queries, [
        "pr",
        "list",
        "--repo",
        repository,
        "--head",
        branch,
        "--state",
        "all",
        "--limit",
        "100",
        "--json",
        PR_FIELDS,
      ]);
      for (const pr of found) {
        // Branch names are not unique across forks. Only show PRs whose head
        // repository is one of this checkout's remotes, not somebody else's fork.
        if (
          pr.headRefName === branch &&
          knownHeads.has(pr.headRepository?.nameWithOwner?.toLowerCase())
        ) {
          candidates.push({ ...pr, repository });
        }
      }
    }
    const matches = [
      ...new Map(candidates.map((pr) => [pr.id ?? `${pr.repository}#${pr.number}`, pr])).values(),
    ].sort((a, b) => (b.updatedAt ?? "").localeCompare(a.updatedAt ?? ""));
    // A reused branch should show its current PR, not a historical merged one.
    const open = matches.filter((pr) => pr.state === "OPEN");
    return open.length ? open : matches.slice(0, 1);
  }

  query(queries, args) {
    const key = JSON.stringify(args);
    if (!queries.has(key)) {
      queries.set(key, exec("gh", args, { timeout: 20000 }).then((result) => {
        if (result.code !== 0)
          throw new Error((result.stderr || "GitHub unavailable; check gh auth login").trim());
        return JSON.parse(result.stdout);
      }));
    }
    return queries.get(key);
  }
}
