// Which issues this copy is looking at, following the space, its checkout and its
// branch. A token per kind of read lets an old answer finish without replacing
// what's on screen after navigation.
import { exec } from "herdr";
import { identifiersIn, searchQuery } from "./model.js";

// A branch name rarely carries more identifiers than this; each one costs a request.
const MAX_BRANCH_CANDIDATES = 4;

export const discoveryMethods = {
  // Everything below resets when the space, folder or branch changes.
  changeSpace(sp, key, cx) {
    this.rememberView();
    this.restoreSelection = null;
    this.lastUpdated = null;
    // Invalidate in-flight requests before clearing space-specific state.
    this.spaceKey = key;
    this.sp = sp;
    this.loadNewAgents(sp, cx);
    this.listToken++;
    this.detailToken++;
    this.branchToken++;
    this.searchToken++;
    this.branchLoading = false;
    this.searchPending = false;
    this.serverSearch = searchQuery(this.search.value());
    this.branch = null;
    this.branchIssues = [];
    this.linkedIdentifiers = new Set();
    this.listLoaded = false;
    this.branchLoaded = false;
    this.contextSince = Date.now();
    this.notice = null;
    this.issue = null;
    this.opening = null;
    this.items = [];
    this.cursor = "";
    this.error = null;
    this.loading = false;
    this.detailLoading = false;
    this.worktreeForm = null;
    this.worktrees = null;
    this.composer = null;
    this.draftKey = null;
    this.section = "overview";
    if (!sp?.folder) {
      this.listLoaded = true;
      this.branchLoaded = true;
      cx.notify();
      return;
    }
    this.restoreView();
    this.refresh(cx);
  },

  soleBranchIssue() {
    return this.view === "branch" && this.branchIssues.length === 1 ? this.branchIssues[0] : null;
  },

  // A branch with one issue has nothing to choose from, so its details are the view.
  openSoleBranchIssue(cx) {
    const sole = this.soleBranchIssue();
    if (!sole || this.issue || this.opening || this.detailLoading) return;
    this.opening = { identifier: sole.identifier };
    this.openIssue(sole.identifier, cx);
  },

  // The branch's issues: an explicit `branch.<name>.herdr-issue` binding first, then
  // identifiers in the branch name. Linear confirms each; the rest are dropped.
  loadBranchIssues(cx) {
    if (!this.sp?.folder || this.mutating) return;
    const token = ++this.branchToken;
    const sp = this.sp;
    const key = this.spaceKey;
    this.branchLoading = true;
    cx.spawn(async (cx) => {
      try {
        const options = { cwd: sp.folder, on: sp.machine };
        const result = await exec("git", ["symbolic-ref", "--quiet", "--short", "HEAD"], options);
        if (token !== this.branchToken || key !== this.spaceKey) return;
        this.branch = result.code === 0 ? result.stdout.trim() : "";
        if (!this.branch) {
          this.branchIssues = [];
          return;
        }
        const binding = await exec(
          "git",
          ["config", "--get", `branch.${this.branch}.herdr-issue`],
          options,
        );
        const bound = identifiersIn(binding.stdout ?? "");
        const named = identifiersIn(this.branch);
        const limit = Math.max(
          bound.length,
          this.settings.branch.max_identifiers || MAX_BRANCH_CANDIDATES,
        );
        const candidates = [...new Set([...bound, ...named])].slice(0, limit);
        const found = candidates.length
          ? (await this.api({ action: "resolve", identifiers: candidates }, sp)).items
          : [];
        if (token !== this.branchToken || key !== this.spaceKey) return;
        this.branchIssues = found;
        // Only a binding can be undone; an identifier in the branch name would come back.
        this.linkedIdentifiers = new Set(bound.filter((id) => !named.includes(id)));
      } catch (e) {
        if (token === this.branchToken) this.error = e.message;
      } finally {
        if (token === this.branchToken) {
          this.branchLoading = false;
          this.branchLoaded = true;
          this.refreshed = Date.now();
          this.openSoleBranchIssue(cx);
          cx.notify();
        }
      }
    });
  },

  // Bind an issue to the branch by hand. The binding is a comma-separated list, so a
  // branch can carry several.
  linkIssue(cx) {
    const identifier = identifiersIn(this.linkInput.value())[0];
    if (!identifier || !this.branch || this.mutating) return;
    const sp = this.sp;
    const key = `branch.${this.branch}.herdr-issue`;
    this.mutating = true;
    this.error = null;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        await this.api({ action: "detail", identifier }, sp);
        const options = { cwd: sp.folder, on: sp.machine };
        const current = await exec("git", ["config", "--get", key], options);
        const list = [...new Set([...identifiersIn(current.stdout ?? ""), identifier])].join(",");
        const written = await exec("git", ["config", key, list], options);
        if (written.code !== 0)
          throw new Error(written.stderr?.trim() || "Could not write the branch binding.");
        this.linkInput.set_value("");
        this.mutating = false;
        this.loadBranchIssues(cx);
      } catch (e) {
        this.error = e.message;
      } finally {
        this.mutating = false;
        cx.notify();
      }
    });
  },

  // Remove a hand-made binding. The git config key is dropped when it empties.
  unlinkIssue(identifier, cx) {
    if (!this.branch || this.mutating) return;
    const sp = this.sp;
    const key = `branch.${this.branch}.herdr-issue`;
    this.mutating = true;
    this.error = null;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const options = { cwd: sp.folder, on: sp.machine };
        const current = await exec("git", ["config", "--get", key], options);
        const rest = identifiersIn(current.stdout ?? "").filter((id) => id !== identifier);
        const written = await exec(
          "git",
          rest.length ? ["config", key, rest.join(",")] : ["config", "--unset", key],
          options,
        );
        if (written.code !== 0)
          throw new Error(written.stderr?.trim() || "Could not update the branch binding.");
        this.issue = null;
        this.mutating = false;
        this.loadBranchIssues(cx);
      } catch (e) {
        this.error = e.message;
      } finally {
        this.mutating = false;
        cx.notify();
      }
    });
  },
};
