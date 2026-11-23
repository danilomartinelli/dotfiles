// Which repository and PR this copy is looking at, following the space, its
// checkout and its branch. A token per kind of read lets an old answer finish
// without replacing what's on screen after navigation.
import { exec } from "herdr";
import { repositoryFromRemote, searchQuery } from "./model.js";

export const discoveryMethods = {
  changeSpace(sp, key, cx) {
    this.leavePR();
    this.rememberView();
    this.browseKey = null;
    this.restoreSelection = null;
    this.pendingPR = null;
    this.lastUpdated = null;
    // Invalidate in-flight requests before clearing repository-specific state.
    this.spaceKey = key;
    this.sp = sp;
    this.loadNewAgents(sp, cx);
    this.listToken++;
    this.detailToken++;
    this.repoToken++;
    this.branchToken++;
    this.searchToken++;
    this.repoLoading = false;
    this.branchLoading = false;
    this.searchPending = false;
    this.searchReloadNeeded = false;
    this.serverSearch = searchQuery(this.search.value());
    this.branch = null;
    this.branchPRs = [];
    this.listLoaded = false;
    this.branchLoaded = false;
    this.contextSince = Date.now();
    this.remotes = [];
    this.remote = "";
    this.notice = null;
    this.repo = "";
    this.pr = null;
    this.items = [];
    this.error = null;
    this.loading = false;
    this.detailLoading = false;
    this.worktreeForm = null;
    this.composer = null;
    this.draftKey = null;
    this.jobs = {};
    this.logs = {};
    this.section = "overview";
    if (!sp?.folder) {
      this.listLoaded = true;
      this.branchLoaded = true;
      cx.notify();
      return;
    }
    this.refresh(cx);
  },

  async detectRepo(sp) {
    const options = { cwd: sp.folder, on: sp.machine };
    const remote = (name) => exec("git", ["remote", "get-url", name], options);
    let result = await remote("upstream");
    if (result.code !== 0) {
      const branch = await exec("git", ["symbolic-ref", "--quiet", "--short", "HEAD"], options);
      if (branch.code === 0) {
        const tracking = await exec(
          "git",
          ["config", "--get", `branch.${branch.stdout.trim()}.remote`],
          options,
        );
        if (tracking.code === 0 && tracking.stdout.trim() !== ".")
          result = await remote(tracking.stdout.trim());
      }
      if (result.code !== 0) result = await remote("origin");
    }
    if (result.code !== 0) throw new Error("No GitHub remote found for this directory.");
    return repositoryFromRemote(result.stdout);
  },

  soleBranchPR() {
    return this.view === "branch" && this.branchPRs.length === 1 ? this.branchPRs[0] : null;
  },

  // A branch with one PR has nothing to choose from, so its details are the view.
  openSoleBranchPR(cx) {
    const sole = this.soleBranchPR();
    if (!sole || this.pr || this.opening || this.detailLoading) return;
    this.opening = { number: sole.number };
    this.openPR(sole.number, cx, sole.repository ?? this.repo);
  },

  // The PRs from this checkout's branch. A worktree made for a PR records its exact
  // association, which beats searching by branch name, ambiguous across forks.
  loadBranchPRs(cx) {
    if (!this.sp?.folder || this.mutating) return;
    const token = ++this.branchToken;
    const sp = this.sp;
    const key = this.spaceKey;
    const options = { cwd: sp.folder, on: sp.machine };
    this.branchLoading = true;
    cx.spawn(async (cx) => {
      try {
        const result = await exec("git", ["symbolic-ref", "--quiet", "--short", "HEAD"], options);
        if (token !== this.branchToken || key !== this.spaceKey) return;
        this.branch = result.code === 0 ? result.stdout.trim() : "";
        if (!this.branch) {
          this.branchPRs = [];
          return;
        }
        const binding = await exec(
          "git",
          ["config", "--get", `branch.${this.branch}.herdr-pr`],
          options,
        );
        const association = /^([\w.-]+\/[\w.-]+)#([1-9][0-9]*)$/.exec(binding.stdout?.trim() ?? "");
        if (association) {
          const linked = await this.api(
            { action: "detail", repo: association[1], number: Number(association[2]) },
            sp,
          );
          if (token !== this.branchToken || key !== this.spaceKey) return;
          this.branchPRs = [{ ...linked, repository: association[1] }];
          return;
        }
        const remotes = await this.discoverRemotes(sp);
        const repositories = [...new Set(remotes.map((r) => r.repo).filter(Boolean))];
        const results = await Promise.allSettled(
          repositories.map((repo) => this.api({ action: "branch", repo, branch: this.branch }, sp)),
        );
        if (token !== this.branchToken || key !== this.spaceKey) return;
        const failures = results.filter((r) => r.status === "rejected");
        // Remote URLs may differ in case from the name the host reports.
        const ours = new Set(repositories.map((repo) => repo.toLowerCase()));
        const matches = results
          .filter((r) => r.status === "fulfilled")
          .flatMap((r) => r.value.items)
          .filter((p) => ours.has(p.headRepository?.nameWithOwner?.toLowerCase()));
        this.branchPRs = [...new Map(matches.map((p) => [p.id, p])).values()].sort(
          (a, b) =>
            (b.state === "OPEN") - (a.state === "OPEN") || b.updatedAt.localeCompare(a.updatedAt),
        );
        if (failures.length) {
          this.notice = `${failures.length} remote repositories could not be checked.`;
          if (!this.branchPRs.length) this.error = failures[0].reason.message;
        }
      } catch (e) {
        if (token === this.branchToken) this.error = e.message;
      } finally {
        if (token === this.branchToken) {
          this.branchLoading = false;
          this.branchLoaded = true;
          this.refreshed = Date.now();
          this.openSoleBranchPR(cx);
          cx.notify();
        }
      }
    });
  },

  remotePreferenceKey() {
    return `pr-remote:${this.sp?.machine ?? "local"}:${this.sp?.folder ?? ""}`;
  },

  async discoverRemotes(sp) {
    const options = { cwd: sp.folder, on: sp.machine };
    const result = await exec("git", ["remote"], options);
    if (result.code !== 0) throw new Error("Cannot read Git remotes for this directory.");
    const names = [...new Set(result.stdout.trim().split(/\r?\n/).filter(Boolean))].sort();
    return Promise.all(
      names.map(async (name) => {
        const url = await exec("git", ["remote", "get-url", name], options);
        try {
          if (url.code !== 0) throw new Error("Unavailable");
          return { name, repo: repositoryFromRemote(url.stdout) };
        } catch {
          return { name, repo: null };
        }
      }),
    );
  },

  chooseRemote(name, cx) {
    const selected = this.remotes.find((r) => r.name === name && r.repo);
    if (!selected || this.mutating) return;
    localStorage.setItem(this.remotePreferenceKey(), name);
    this.repoToken++;
    this.listToken++;
    this.repoLoading = false;
    this.remote = name;
    this.repo = selected.repo;
    this.notice = null;
    this.error = null;
    this.loadList(cx);
    cx.notify();
  },

  resolveRepo(cx) {
    if (!this.sp?.folder) return;
    const token = ++this.repoToken;
    const key = this.spaceKey;
    const sp = this.sp;
    this.repoLoading = true;
    this.error = null;
    cx.spawn(async (cx) => {
      try {
        const [remotes, defaultRepo] = await Promise.all([
          this.discoverRemotes(sp),
          this.detectRepo(sp).catch(() => null),
        ]);
        if (token !== this.repoToken || key !== this.spaceKey) return;
        this.remotes = remotes;
        const preference = localStorage.getItem(this.remotePreferenceKey());
        const selected =
          remotes.find((r) => r.name === preference && r.repo) ??
          remotes.find((r) => r.name === "upstream" && r.repo === defaultRepo) ??
          remotes.find((r) => r.repo && r.repo === defaultRepo) ??
          remotes.find((r) => r.repo);
        if (!selected) throw new Error("No GitHub remote found for this directory.");
        if (preference && !remotes.some((r) => r.name === preference && r.repo))
          localStorage.removeItem(this.remotePreferenceKey());
        this.remote = selected.name;
        const repo = selected.repo;
        this.restoreView(repo);
        if (repo !== this.repo) {
          this.repo = repo;
          this.items = [];
          this.listToken++;
        }
        // Only what's on screen, to spare API quota, plus once for the tab's count.
        if (this.view === "all" || !this.listLoaded) this.loadList(cx);
      } catch (e) {
        if (token === this.repoToken && key === this.spaceKey) {
          this.listToken++;
          this.loading = false;
          this.repo = "";
          this.items = [];
          this.listLoaded = true;
          this.error = e.message;
          this.refreshed = Date.now();
        }
      } finally {
        if (token === this.repoToken) {
          this.repoLoading = false;
          cx.notify();
        }
      }
    });
  },
};
