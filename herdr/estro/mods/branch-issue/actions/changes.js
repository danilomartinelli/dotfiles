// What this panel writes to Linear, always from an explicit click: state, priority
// and assignee, and comments and replies.
export const changeMethods = {
  // These write on choice. The helper returns the new values, merged into every copy
  // of the issue held here.
  update(fields, label, cx) {
    if (!this.issue || this.mutating) return;
    const issue = this.issue;
    const key = this.spaceKey;
    this.mutating = true;
    this.error = null;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const data = await this.api({ action: "update", issue: issue.id, ...fields });
        const updated = data?.issueUpdate?.issue;
        if (key !== this.spaceKey || this.issue?.id !== issue.id) return;
        if (updated) {
          this.issue = { ...this.issue, ...updated };
          this.branchIssues = this.branchIssues.map((i) => (i.id === issue.id ? this.issue : i));
          this.items = this.items.map((i) => (i.id === issue.id ? { ...i, ...updated } : i));
        }
        this.notice = `${label} saved to Linear.`;
      } catch (e) {
        if (key === this.spaceKey) this.error = e.message;
      } finally {
        this.mutating = false;
        cx.notify();
      }
    });
  },

  // `kind` is reply or agent. Drafts are kept per issue, kind and target, so
  // an abandoned reply survives navigation.
  compose(kind, parent, context, cx, options = {}) {
    if (this.mutating) return;
    this.composer = { kind, parent, context, ...options };
    this.target = options.target ?? null;
    this.draftKey = `linear-draft:${this.spaceKey}:${this.issue.id}:${kind}:${parent ?? "general"}:${options.target ?? ""}`;
    const draft = localStorage.getItem(this.draftKey);
    const initial =
      kind === "agent"
        ? "Analyze this issue and suggest how to approach it."
        : (options.prefix ?? "");
    const text = draft ?? initial;
    this.editor.set_value(text);
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

  mutate(cx) {
    if (!this.composer) return;
    const draft = this.draftKey;
    this.writeComment(this.editor.value(), this.composer.parent ?? "", cx, () => {
      localStorage.removeItem(draft);
      this.composer = null;
      this.draftKey = null;
    });
  },

  postComment(cx) {
    const draft = this.commentKey;
    this.writeComment(this.newComment.value(), "", cx, () => {
      this.newComment.set_value("");
      localStorage.removeItem(draft);
    });
  },

  // The draft is only cleared once Linear has accepted it.
  writeComment(body, parent, cx, saved) {
    if (this.mutating) return;
    const key = this.spaceKey;
    const issue = this.issue;
    this.mutating = true;
    this.error = null;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        await this.api({ action: "comment", issue: issue.id, body, parent });
        if (key !== this.spaceKey || issue.id !== this.issue?.id) return;
        saved();
        this.notice = "Saved to Linear.";
        this.openIssue(issue.identifier, cx);
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
