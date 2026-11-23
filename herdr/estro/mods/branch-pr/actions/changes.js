// What this panel writes to GitHub, always from an explicit click: merging and
// closing, re-requesting a review, and comments, replies and resolving.
import { STATE_CHANGES } from "../github/model.js";

export const changeMethods = {
  // Merge, close and reopen go through a confirmation row: they reach everyone
  // on the PR, and a merge cannot be taken back.
  askStateChange(event, cx) {
    this.stateChange = {
      event,
      repo: this.pr.repository,
      number: this.pr.number,
      head: this.pr.headRefOid,
    };
    if (event === "squash") {
      const { title, number, body } = this.pr;
      const subject = `${title} (#${number})`;
      this.squashMessage.set_value(body?.trim() ? `${subject}\n\n${body.trim()}` : subject);
      this.squashMessage.focus();
    }
    this.error = null;
    cx.notify();
  },

  changeState(cx) {
    const change = this.stateChange;
    if (!change || this.mutating) return;
    const key = this.spaceKey;
    this.mutating = true;
    this.error = null;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        await this.api({
          action: "change-state",
          repo: change.repo,
          number: change.number,
          event: change.event,
          head: change.head,
          ...(change.event === "squash" ? { body: this.squashMessage.value().trim() } : {}),
          ...(change.event === "auto"
            ? { method: this.pr.mergeMethods?.[0] ?? "merge", id: this.pr.id }
            : {}),
        });
        if (key !== this.spaceKey) return;
        this.stateChange = null;
        this.notice = STATE_CHANGES[change.event].done;
        this.items = []; // the list shows this PR's old state until it reloads
        this.openPR(change.number, cx, change.repo);
      } catch (e) {
        if (key === this.spaceKey)
          this.error = `${e.message}. Refresh before retrying if it may have gone through.`;
      } finally {
        this.mutating = false;
        cx.notify();
      }
    });
  },

  requestReviewAgain(reviewer, cx) {
    if (this.mutating || !this.pr) return;
    const key = this.spaceKey;
    const repo = this.pr.repository;
    const number = this.pr.number;
    this.mutating = true;
    this.error = null;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        await this.api({ action: "reviewer", repo, number, reviewer });
        if (key !== this.spaceKey) return;
        this.notice = `Asked ${reviewer} to review again.`;
        this.openPR(number, cx, repo);
      } catch (e) {
        if (key === this.spaceKey) this.error = e.message;
      } finally {
        this.mutating = false;
        cx.notify();
      }
    });
  },

  compose(kind, thread, context, cx, options = {}) {
    if (this.mutating) return;
    this.composer = { kind, thread, context, ...options };
    this.target = options.target ?? null;
    this.draftKey = `pr-draft:${this.spaceKey}:${this.pr.repository}:${this.pr.id}:${kind}:${thread ?? "general"}:${options.entry ?? ""}:${options.target ?? ""}`;
    const draft = localStorage.getItem(this.draftKey);
    const initial =
      kind === "agent"
        ? "Analyze this comment and suggest a response or fix."
        : (options.prefix ?? "");
    const text = draft ?? initial;
    this.editor.set_value(text);
    // After a prefilled `@name`, so what's typed follows it.
    this.editor.set_selected_range({ start: text.length, end: text.length });
    this.editor.focus();
    cx.notify();
  },

  closeComposer(cx) {
    if (this.mutating) return;
    this.composer = null;
    this.draftKey = null;
    cx.notify();
  },

  postComment(cx) {
    const draft = this.commentKey;
    this.mutate("comment", cx, undefined, {
      body: this.newComment.value(),
      saved: () => {
        this.newComment.set_value("");
        localStorage.removeItem(draft);
      },
    });
  },

  mutate(action, cx, thread, { body = this.editor.value(), saved } = {}) {
    if (this.mutating) return;
    const key = this.spaceKey;
    const repo = this.pr.repository;
    const number = this.pr.number;
    const draft = this.draftKey;
    this.mutating = true;
    this.error = null;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        await this.api({ action, repo, number, thread, body });
        if (key !== this.spaceKey || repo !== this.pr?.repository || number !== this.pr?.number)
          return;
        if (saved) saved();
        else if (action === "comment" || action === "reply") {
          localStorage.removeItem(draft);
          this.composer = null;
          this.draftKey = null;
        }
        this.notice = "Saved to GitHub.";
        this.openPR(number, cx, repo);
      } catch (e) {
        if (key === this.spaceKey)
          this.error = `${e.message}. Refresh before retrying if the request may have succeeded.`;
      } finally {
        this.mutating = false;
        cx.notify();
      }
    });
  },
};
