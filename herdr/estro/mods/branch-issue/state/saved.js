// What survives a reload: the list's filters and open issue, and each issue's tab.
import { identifiersIn, searchQuery } from "../linear/model.js";

const SECTIONS = ["overview", "comments"];
const SCOPE_IDS = ["mine", "cycle", "all"];
const STATE_IDS = ["active", "backlog", "started", "done", "cancelled", "all"];
const oneOf = (choices, value, fallback) => (choices.includes(value) ? value : fallback);

export const savedMethods = {
  readStored(key, fallback = {}) {
    try {
      const value = JSON.parse(localStorage.getItem(key) ?? "null");
      return value && typeof value === "object" && !Array.isArray(value) ? value : fallback;
    } catch {
      return fallback;
    }
  },

  readStoredList(key) {
    try {
      const value = JSON.parse(localStorage.getItem(key) ?? "[]");
      return Array.isArray(value) ? value : [];
    } catch {
      return [];
    }
  },

  viewKey() {
    return `linear-view:v2:${this.sp?.machine ?? "local"}:${this.sp?.folder ?? ""}`;
  },

  rememberView() {
    if (this.issue)
      localStorage.setItem(
        `linear-detail:v1:${this.issue.id}`,
        JSON.stringify({ section: this.section }),
      );
    if (!this.sp?.folder) return;
    localStorage.setItem(
      this.viewKey(),
      JSON.stringify({
        scope: this.scope,
        state: this.state,
        team: this.team,
        query: this.search.value(),
        selected: this.issue?.identifier ?? this.opening?.identifier ?? null,
      }),
    );
  },

  restoreView() {
    const saved = this.readStored(this.viewKey());
    this.viewWasSaved = Boolean(saved.scope || saved.state);
    const wanted = this.settings.list.default;
    this.scope = oneOf(SCOPE_IDS, saved.scope, oneOf(SCOPE_IDS, wanted.scope, "mine"));
    this.state = oneOf(STATE_IDS, saved.state, oneOf(STATE_IDS, wanted.state, "active"));
    this.team = typeof saved.team === "string" ? saved.team : wanted.team;
    // Restoring text fires the same change event as typing; the caller is already
    // about to load this view.
    this.restoringSearch = true;
    this.search.set_value(typeof saved.query === "string" ? saved.query : "");
    this.restoringSearch = false;
    this.serverSearch = searchQuery(this.search.value());
    this.restoreSelection = identifiersIn(saved.selected ?? "")[0] ?? null;
  },

  adoptIssue(issue) {
    if (this.issue?.id !== issue.id) {
      const saved = this.readStored(`linear-detail:v1:${issue.id}`);
      this.section = oneOf(SECTIONS, saved.section, SECTIONS[0]);
      this.composer = null;
      this.draftKey = null;
      // Cleared first so that restoring the draft doesn't write it to the old issue's key.
      this.commentKey = null;
      const commentKey = `linear-draft:${this.spaceKey}:${issue.id}:comment`;
      this.newComment.set_value(localStorage.getItem(commentKey) ?? "");
      this.commentKey = commentKey;
    }
    this.issue = issue;
    this.lastUpdated = Date.now();
    this.rememberView();
  },

  selectSection(section, cx) {
    this.section = section;
    this.notice = null;
    this.rememberView();
    cx.notify();
  },

  // Which Overview and list groups are shut, the same for every issue.
  toggleGroup(key, cx) {
    if (!this.closedGroups.delete(key)) this.closedGroups.add(key);
    localStorage.setItem("closed-groups", JSON.stringify([...this.closedGroups]));
    cx.notify();
  },

  backToList(cx) {
    if (this.mutating) return;
    this.rememberView();
    this.issue = null;
    this.opening = null;
    this.notice = null;
    this.detailToken++;
    this.detailLoading = false;
    this.composer = null;
    this.draftKey = null;
    this.worktreeForm = null;
    this.rememberView();
    cx.notify();
  },

  close() {
    this.rememberView();
  },

  updatedLabel() {
    if (!this.lastUpdated) return "Not updated yet";
    const seconds = Math.max(0, Math.floor((Date.now() - this.lastUpdated) / 1000));
    return seconds < 60
      ? "Updated just now"
      : seconds < 3600
        ? `Updated ${Math.floor(seconds / 60)}m ago`
        : `Updated ${new Date(this.lastUpdated).toLocaleTimeString()}`;
  },
};
