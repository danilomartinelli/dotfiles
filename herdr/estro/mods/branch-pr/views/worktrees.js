// The Overview's worktrees: a row per checkout, and the form for a new one.
import { div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, theme } from "herdr";
import { TEXT, Button, Row, TextButton, TextField } from "./ui.js";
import { slug } from "../actions/worktrees.js";

export const worktreeViewMethods = {
  worktreeRows(body) {
    const list = this.currentWorktrees();
    const form = this.worktreeForm;
    const formOpen = form && form.pr.id === this.pr?.id && form.repo === this.pr?.repository;
    const action = formOpen
      ? null
      : TextButton({
          id: "pr-create-worktree",
          icon: "checkout",
          label: "New worktree",
          onClick: (cx) => this.showWorktree(cx),
        });
    const info = { key: "worktrees", label: "Worktrees", count: list.length, action };
    this.group(body, info, (into) => this.worktreeList(into, list, formOpen ? form : null));
  },

  worktreeList(body, list, form) {
    const t = theme();
    list.forEach((worktree, i) => {
      const space = this.worktreeSpace(worktree);
      body.child(
        Row({
          id: `pr-worktree-row-${i}`,
          onClick: (cx) => {
            if (space) run("space.select", { id: space.id });
            else
              run("space.new", {
                folder: worktree.path,
                machine: this.sp?.machine ?? "",
                tab: worktree.name,
              });
            cx.notify();
          },
        })
          .tooltip(space ? `Switch to ${worktree.path}` : `Open ${worktree.path} as a space`)
          .child(div().flex_none().child(worktree.name))
          .child(
            div()
              .flex_1()
              .min_w(0)
              .truncate()
              .text_right()
              .text_size(TEXT.small)
              .text_color(t.dim)
              .child(worktree.branch),
          ),
      );
    });
    if (form) body.child(this.worktreeFormView(form));
  },

  worktreeFormView(form) {
    const t = theme();
    const close = (cx) => {
      this.worktreeForm = null;
      cx.notify();
    };
    const choices = this.launchChoices(form);
    const current = choices.find((c) => c.key === form.launch) ?? choices[0];
    const location =
      form.path ??
      `${form.root.replace(/\/+$/, "")}/${form.repo.replace(/\//g, "-")}/${slug(form.name.value().trim())}`;
    const box = v_flex()
      .id("pr-worktree-form")
      .flex_none()
      .mx(8)
      .my(4)
      .p(10)
      .gap(8)
      .rounded(8)
      .border_1()
      .border_color(t.border)
      .bg(t.raised);
    const field = (id, label, state) =>
      h_flex()
        .gap(8)
        .items_center()
        .child(div().w(62).flex_none().text_size(TEXT.small).text_color(t.dim).child(label))
        .child(TextField({ id: `pr-worktree-${id}`, state, height: 28 }));
    if (!form.path)
      box.child(field("branch", "Branch", form.branch)).child(field("name", "Worktree", form.name));
    box.child(
      div()
        .text_size(TEXT.caption)
        .text_color(form.error ? t.ansi1 : form.path ? t.done : t.dim)
        .whitespace_normal()
        .child(form.error ?? (form.path ? `Checkout ready at ${form.path}` : location)),
    );
    const actions = h_flex().gap(8).items_center().justify_end().flex_wrap();
    if (!form.opened)
      actions.child(
        this.chooser({
          id: "pr-worktree-launch",
          prefix: "Open with",
          label: current.name,
          accessibilityLabel: "Open the worktree with",
          width: 200,
          choices: choices.map((c) => ({ id: c.key, label: c.name })),
          value: form.launch,
          onChoose: (key) => {
            form.launch = key;
          },
        }),
      );
    actions.child(
      Button({
        id: "pr-worktree-cancel",
        label: form.path ? "Done" : "Cancel",
        disabled: form.busy,
        onClick: close,
      }),
    );
    if (!form.path)
      actions.child(
        Button({
          id: "pr-worktree-submit",
          label: form.busy ? "Creating…" : "Create",
          primary: true,
          disabled: form.busy,
          onClick: (cx) => this.createWorktree(cx),
        }),
      );
    else if (!form.opened)
      actions.child(
        Button({
          id: "pr-worktree-open",
          label: `Open ${current.name}`,
          primary: true,
          onClick: (cx) => this.openWorktree(form, cx),
        }),
      );
    return box.child(actions);
  },
};
