// The Comments tab: everything said on the issue, and answering it or handing it on.
import { div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { theme } from "herdr";
import { commentThreads, timeAgo, who } from "../linear/model.js";
import { agentName } from "../actions/agents.js";
import { TEXT, Button, IconButton, Markdown, Message, TextBox, TextButton } from "./ui.js";

export const commentMethods = {
  commentBlock(comment, reply, t) {
    return v_flex()
      .gap(4)
      .min_w(0)
      .when(reply, (el) => el.pl(12).border_l(2).border_color(t.border))
      .child(
        h_flex()
          .gap(6)
          .items_center()
          .child(div().flex_none().font_medium().text_size(TEXT.small).child(who(comment)))
          .child(
            div()
              .flex_1()
              .min_w(0)
              .truncate()
              .text_size(TEXT.caption)
              .text_color(t.dim)
              .child(timeAgo(comment.createdAt)),
          )
          .when(Boolean(comment.url), (el) =>
            el.child(
              IconButton({
                id: `issue-copy-${comment.id}`,
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
      .child(Markdown(`issue-comment-${comment.id}`, comment.body || "No comment text."));
  },

  threadActions(root, thread) {
    const last = thread[thread.length - 1];
    const context = thread.map((c) => `${who(c)}: ${c.body}`).join("\n\n");
    return h_flex()
      .gap(2)
      .items_center()
      .child(
        TextButton({
          id: `issue-reply-${root.id}`,
          label: "Reply",
          disabled: this.mutating,
          onClick: (cx) =>
            this.compose("reply", root.id, null, cx, { entry: root.id, url: last.url }),
        }),
      )
      .child(div().flex_1())
      .child(
        this.agentButton({
          id: `issue-agent-send-${root.id}`,
          label: "Send to agent",
          send: (agent, cx) =>
            this.compose("agent", root.id, context, cx, {
              entry: root.id,
              url: last.url,
              target: agent.address,
            }),
        }),
      );
  },

  commentsView(body, issue) {
    const t = theme();
    const threads = commentThreads(issue);
    if (!threads.length) body.child(Message("No comments yet."));
    threads.forEach((thread, i) => {
      const [root] = thread;
      const block = v_flex()
        .id(`comment-${root.id}`)
        .flex_none()
        .min_w(0)
        .px(8)
        .py(10)
        .gap(10)
        .when(i > 0, (el) => el.border_t(1).border_color(t.border))
        .children(thread.map((c, n) => this.commentBlock(c, n > 0, t)))
        .child(this.threadActions(root, thread));
      if (this.composer?.entry === root.id) block.child(this.composerView());
      body.child(block);
    });
    body.child(this.newCommentBox(threads.length > 0));
  },

  // Always here after the last comment, so saying something takes no extra click.
  newCommentBox(divided) {
    const t = theme();
    const posting = this.mutating && !this.composer;
    return v_flex()
      .id("issue-new-comment")
      .flex_none()
      .min_w(0)
      .px(8)
      .py(10)
      .gap(8)
      .when(divided, (el) => el.border_t(1).border_color(t.border))
      .child(TextBox({ id: "issue-comment-input", state: this.newComment, label: "New comment" }))
      .child(
        h_flex()
          .justify_end()
          .child(
            Button({
              id: "issue-add-comment",
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
      .id(`issue-composer-${composer.entry ?? "general"}`)
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
      .child(TextBox({ id: "issue-inline-input", state: this.editor, label: "Message" }))
      .child(
        h_flex()
          .gap(8)
          .justify_end()
          .child(
            Button({
              id: "issue-cancel",
              label: "Close",
              disabled: this.mutating,
              onClick: (cx) => this.closeComposer(cx),
            }),
          )
          .child(
            Button({
              id: "issue-submit",
              label: this.mutating ? "Sending…" : toAgent ? "Send" : "Reply",
              primary: true,
              disabled,
              onClick: (cx) => (toAgent ? this.sendAgent(cx) : this.mutate(cx)),
            }),
          ),
      );
  },
};
