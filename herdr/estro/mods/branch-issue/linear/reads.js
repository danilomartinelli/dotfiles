// Reads through the helper, which holds the key and the GraphQL. The key and the
// helper stay on this computer, including for remote spaces.
import { exec, appHome } from "herdr";
import { duration } from "../settings.js";
import { searchQuery } from "./model.js";

const SEARCH_DEBOUNCE_MS = 450;

export const readMethods = {
  async api(request, sp = this.sp) {
    const result = await exec(
      `${appHome()}/mods/branch-issue/bin/herdr-linear`,
      [JSON.stringify(request)],
      { cwd: sp?.machine ? undefined : sp?.folder },
    );
    let data;
    try {
      data = JSON.parse(result.stdout);
    } catch {
      throw new Error(result.stderr || "Linear helper returned invalid JSON");
    }
    if (result.code !== 0 || data.error)
      throw new Error(data.error || result.stderr || "Linear request failed");
    return data;
  },

  // Viewer and teams load once per panel: the team filter and the "Me" assignee.
  async ensureViewer() {
    if (this.me) return;
    const data = await this.api({ action: "viewer" });
    this.me = data.viewer;
    this.teams = data.teams ?? [];
  },

  searchChanged(cx) {
    const token = ++this.searchToken;
    this.rememberView();
    this.searchPending = true;
    const wasLoading = this.loading;
    this.listToken++;
    this.loading = false;
    cx.timer.after(duration(this.settings.refresh.search_debounce, SEARCH_DEBOUNCE_MS), (cx) => {
      if (token !== this.searchToken) return;
      const query = searchQuery(this.search.value());
      this.searchPending = false;
      if (wasLoading || query !== (this.serverSearch ?? "")) {
        this.serverSearch = query;
        this.loadList(cx);
      }
      cx.notify();
    });
    cx.notify();
  },

  listKey() {
    return `${this.spaceKey}:${this.scope}:${this.state}:${this.team}:${this.serverSearch ?? ""}`;
  },

  // A refresh re-reads page one and keeps any further pages already loaded.
  // shortcut: an item that left the filter stays until the next full load.
  loadList(cx, more = false, refresh = false) {
    if (!this.sp?.folder) return;
    this.rememberView();
    const token = ++this.listToken;
    const key = this.spaceKey;
    const list = this.listKey();
    this.loading = true;
    this.error = null;
    if (!more && !refresh) {
      this.items = this.cache[list]?.items ?? [];
      this.cursor = this.cache[list]?.cursor ?? "";
    }
    const request = {
      action: "list",
      scope: this.scope,
      state: this.state,
      team: this.team,
      search: this.serverSearch ?? "",
      cursor: more ? this.cursor : "",
    };
    cx.spawn(async (cx) => {
      try {
        await this.ensureViewer();
        const data = await this.api(request);
        if (token !== this.listToken || key !== this.spaceKey) return;
        const keep = refresh && this.items.length > data.items.length;
        const merged = new Map((more || keep ? this.items : []).map((i) => [i.id, i]));
        for (const item of data.items) merged.set(item.id, item);
        this.items = [...merged.values()];
        if (!keep) this.cursor = data.cursor ?? "";
        this.cache[list] = { items: this.items, cursor: this.cursor };
        this.refreshed = Date.now();
        this.lastUpdated = Date.now();
        // Only the first time: a branch change should show the list, not an old issue.
        const restore = this.reopenSaved ? this.restoreSelection : null;
        this.reopenSaved = false;
        this.restoreSelection = null;
        if (restore && !this.issue && !this.opening) this.openIssue(restore, cx);
        else this.rememberView();
      } catch (e) {
        if (token === this.listToken) {
          this.error = e.message;
          this.refreshed = Date.now();
        }
      } finally {
        if (token === this.listToken) {
          this.loading = false;
          this.listLoaded = true;
          cx.notify();
        }
      }
    });
  },

  openIssue(identifier, cx) {
    const token = ++this.detailToken;
    const key = this.spaceKey;
    this.detailLoading = true;
    this.error = null;
    cx.spawn(async (cx) => {
      try {
        await this.ensureViewer();
        const issue = await this.api({ action: "detail", identifier });
        if (token !== this.detailToken || key !== this.spaceKey) return;
        this.adoptIssue(issue);
        this.refreshed = Date.now();
        this.loadWorktrees(cx);
      } catch (e) {
        if (token === this.detailToken) {
          this.error = e.message;
          this.refreshed = Date.now();
        }
      } finally {
        if (token === this.detailToken) {
          this.detailLoading = false;
          this.opening = null;
          cx.notify();
        }
      }
    });
  },

  refresh(cx) {
    this.loadBranchIssues(cx);
    // Only what's on screen, to spare API quota, plus once for the tab's count.
    if (this.view === "all" || !this.listLoaded) this.loadList(cx, false, this.listLoaded);
    if (this.issue) this.openIssue(this.issue.identifier, cx);
  },
};
