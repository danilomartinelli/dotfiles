// The Comments tab: everything said on the PR, and answering it or handing it on.
import { div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { theme } from "herdr";
import {
  authorsOf,
  conversationEntries,
  entryContext,
  timeAgo,
  unresolvedThreads,
  who,
} from "../github/model.js";
import { agentName } from "../actions/agents.js";
import {
  TEXT,
  Button,
  Chevron,
  CodeBlock,
  IconButton,
  Markdown,
  Message,
  TextBox,
  TextButton,
  codeFont,
} from "./ui.js";

// A comment is about the end of its hunk, which can run to hundreds of lines.
const HUNK_LINES = 6;
const lastLines = (hunk) => hunk.split("\n").slice(-HUNK_LINES).join("\n");

export const conversationMethods = {
  conversationFilters(pr) {
    const t = theme();
    const authors = ["", ...authorsOf(pr)];
    const unresolved = unresolvedThreads(pr).length;
    // One line when there's room; the buttons wrap to the right when there isn't.
    return h_flex()
      .id("pr-comment-filters")
      .flex_none()
      .px(14)
      .py(8)
      .gap(8)
      .flex_wrap()
      .items_center()
      .border_b(1)
      .border_color(t.border)
      .child(
        h_flex()
          .flex_none()
          .gap(6)
          .items_center()
          .child(
            this.chooser({
              id: "pr-author",
              prefix: "Author",
              label: this.author || "All",
              accessibilityLabel: "Filter by author",
              anchor: "top_left",
              width: 220,
              small: true,
              choices: authors.map((a) => ({ id: a || "all", label: a || "All authors" })),
              value: this.author || "all",
              triggerFocus: this.authorTrigger,
              onChoose: (id) => {
                this.author = id === "all" ? "" : id;
                this.rememberDetail();
              },
            }),
          )
          .child(
            TextButton({
              id: "pr-unresolved",
              label: "Unresolved",
              active: Boolean(this.unresolved),
              onClick: (cx) => {
                this.unresolved = !this.unresolved;
                this.rememberDetail();
                cx.notify();
              },
            }),
          )
          .when(Boolean(this.unreadIds?.size), (el) =>
            el.child(
              TextButton({
                id: "pr-mark-read",
                label: `Mark ${this.unreadIds.size} read`,
                onClick: (cx) => {
                  this.markRead();
                  cx.notify();
                },
              }),
            ),
          ),
      )
      .child(
        h_flex()
          .flex_none()
          .ml_auto()
          .gap(6)
          .items_center()
          .when(unresolved > 0, (el) =>
            el.child(
              this.agentButton({
                id: "pr-send-unresolved",
                label: `Send ${unresolved} to agent`,
                send: (agent, cx) => this.sendUnresolved(agent, cx),
              }),
            ),
          ),
      );
  },

  commentBlock(comment, t) {
    return v_flex()
      .gap(4)
      .min_w(0)
      .child(
        h_flex()
          .gap(6)
          .items_center()
          .child(
            div()
              .flex_none()
              .font_medium()
              .text_size(TEXT.small)
              .text_color(this.author === who(comment) ? t.accent : t.foreground)
              .child(who(comment)),
          )
          .when(Boolean(this.unreadIds?.has(comment.id)), (el) =>
            el.child(div().flex_none().text_size(TEXT.caption).text_color(t.accent).child("New")),
          )
          .child(
            div()
              .flex_1()
              .min_w(0)
              .truncate()
              .text_size(TEXT.caption)
              .text_color(t.dim)
              .child(timeAgo(comment.createdAt ?? comment.submittedAt)),
          )
          .when(Boolean(comment.url), (el) =>
            el.child(
              IconButton({
                id: `pr-copy-${comment.id}`,
                icon: "copy",
                label: "Copy link",
                small: true,
                onClick: (cx) => {
                  cx.write_to_clipboard(comment.url);
                  this.notice = "Comment link copied.";
                  cx.notify();
                },
              }),
            ),
          ),
      )
      .child(Markdown(`pr-comment-${comment.id}`, comment.body || "No comment text."));
  },

  entryActions(entry, comments) {
    const thread = entry.thread;
    const last = comments[comments.length - 1];
    const url = last?.url || comments[0]?.url || this.pr.url;
    const row = h_flex()
      .gap(2)
      .items_center()
      .child(
        TextButton({
          id: `pr-reply-${entry.id}`,
          label: "Reply",
          disabled: this.mutating || Boolean(thread && !thread.viewerCanReply),
          onClick: (cx) =>
            this.compose(thread ? "reply" : "comment", thread?.id, null, cx, {
              entry: entry.id,
              url,
              prefix: thread ? "" : `@${who(last)} `,
            }),
        }),
      );
    if (thread && (thread.isResolved ? thread.viewerCanUnresolve : thread.viewerCanResolve))
      row.child(
        TextButton({
          id: `pr-resolve-${entry.id}`,
          label: thread.isResolved ? "Reopen" : "Resolve",
          disabled: this.mutating,
          onClick: (cx) => this.mutate(thread.isResolved ? "reopen" : "resolve", cx, thread.id),
        }),
      );
    return row.child(div().flex_1()).child(
      this.agentButton({
        id: `pr-agent-send-${entry.id}`,
        label: "Send to agent",
        send: (agent, cx) =>
          this.compose("agent", thread?.id ?? entry.id, entryContext(entry), cx, {
            entry: entry.id,
            url,
            target: agent.address,
          }),
      }),
    );
  },

  conversationView(body, pr) {
    const t = theme();
    const entries = conversationEntries(pr, { author: this.author, unresolved: this.unresolved });
    if (!entries.length)
      body.child(
        Message(
          this.author || this.unresolved ? "No comments match these filters." : "No comments yet.",
        ),
      );
    entries.forEach((entry, i) => {
      const thread = entry.thread;
      const comments = thread ? thread.comments : [entry];
      // A resolved thread needs nothing from you, so it starts shut.
      const open = this.entryOpen[entry.id] ?? !thread?.isResolved;
      const block = v_flex()
        .id(`conversation-${entry.id}`)
        .flex_none()
        .min_w(0)
        .when(i > 0, (el) => el.mt(4).border_t(1).border_color(t.border))
        .child(
          h_flex()
            .id(`pr-entry-toggle-${entry.id}`)
            .h(32)
            .px(8)
            .gap(6)
            .min_w(0)
            .items_center()
            .cursor_pointer()
            .text_size(TEXT.caption)
            .text_color(thread && !thread.isResolved ? t.working : t.dim)
            .on_click((_e, cx) => {
              this.entryOpen[entry.id] = !open;
              cx.notify();
            })
            .child(Chevron(open))
            .child(div().flex_none().child(entry.kind))
            .when(Boolean(thread), (el) =>
              el.child(
                div()
                  .flex_1()
                  .min_w(0)
                  .truncate()
                  .text_color(t.accent)
                  .font_family(codeFont())
                  .tooltip(`${thread.path}:${thread.line ?? ""}`)
                  .child(`${thread.path}:${thread.line ?? ""}`),
              ),
            )
            .when(!open, (el) =>
              el.child(div().flex_none().text_color(t.dim).child(who(comments[0]))),
            ),
        );
      if (open) {
        const content = v_flex().px(8).pb(10).gap(10).min_w(0);
        const hunk = thread?.comments[0]?.diffHunk;
        if (hunk) content.child(CodeBlock(lastLines(hunk)));
        content.children(comments.map((c) => this.commentBlock(c, t)));
        content.child(this.entryActions(entry, comments));
        if (this.composer?.entry === entry.id) content.child(this.composerView());
        block.child(content);
      }
      body.child(block);
    });
    body.child(this.newCommentBox(entries.length > 0));
  },

  // Always here after the last comment, so saying something takes no extra click.
  newCommentBox(divided) {
    const t = theme();
    const posting = this.mutating && !this.composer;
    return v_flex()
      .id("pr-new-comment")
      .flex_none()
      .min_w(0)
      .px(8)
      .py(10)
      .gap(8)
      .when(divided, (el) => el.mt(4).border_t(1).border_color(t.border))
      .child(TextBox({ id: "pr-comment-input", state: this.newComment, label: "New comment" }))
      .child(
        h_flex()
          .justify_end()
          .child(
            Button({
              id: "pr-add-comment",
              label: posting ? "Sending…" : "Comment",
              primary: true,
              disabled: this.mutating || !this.newComment.value().trim(),
              onClick: (cx) => this.postComment(cx),
            }),
          ),
      );
  },

  dockedComposer() {
    const t = theme();
    return v_flex().flex_none().p(10).border_t(1).border_color(t.border).child(this.composerView());
  },

  composerView() {
    const t = theme();
    const composer = this.composer;
    const toAgent = composer.kind === "agent";
    const agent = toAgent ? this.agentAt(this.target) : null;
    const box = v_flex()
      .id(`pr-composer-${composer.entry ?? "general"}`)
      .gap(8)
      .min_w(0);
    if (toAgent)
      box.child(
        div()
          .text_size(TEXT.small)
          .font_medium()
          .child(agent ? `Send to ${agentName(agent)}` : "That agent is no longer running."),
      );
    if (agent?.status === "working" && !agent.spawn)
      box.child(
        div()
          .text_size(TEXT.caption)
          .text_color(t.dim)
          .child("It's busy; your message waits in its session."),
      );
    const disabled = this.mutating || !this.editor.value().trim() || (toAgent && !agent);
    return box
      .child(TextBox({ id: "pr-inline-input", state: this.editor, label: "Message" }))
      .child(
        h_flex()
          .gap(8)
          .justify_end()
          .child(
            Button({
              id: "pr-cancel",
              label: "Close",
              disabled: this.mutating,
              onClick: (cx) => this.closeComposer(cx),
            }),
          )
          .child(
            Button({
              id: "pr-submit",
              label: this.mutating ? "Sending…" : toAgent ? "Send" : "Reply",
              primary: true,
              disabled,
              onClick: (cx) =>
                toAgent ? this.sendAgent(cx) : this.mutate(composer.kind, cx, composer.thread),
            }),
          ),
      );
  },
};
