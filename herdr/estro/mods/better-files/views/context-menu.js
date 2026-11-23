// The right-click menu: its own small copy of this mod, in a popup at the pointer.
import { div } from "gpui-kit";
import { v_flex } from "gpui-base";
import { closeOverlay, props, shared, theme, window } from "herdr";
import { editorId, foundEditors, ownFileManager } from "../actions/outside.js";
import { revealLabel } from "../files/shell.js";
import { agentName } from "../actions/agents.js";
import { TEXT } from "./ui.js";

export const contextMenuMethods = {
  menuItems(target) {
    const local = !target.on;
    const editors = local ? foundEditors() : [];
    const file = { path: target.path, root: target.root, on: target.on };
    const groups = [];
    if (!target.dir)
      groups.push([
        { id: "open", label: "Open", run: (cx) => this.openFile(file, cx) },
        { id: "open-tab", label: "Open in new tab", run: (cx) => this.openInNewTab(file, cx) },
      ]);
    groups.push([
      ...editors.map((e) => ({
        id: `editor-${editorId(e)}`,
        label: `Open in ${e.name}`,
        run: () => this.openInEditor(e, target.path),
      })),
      ...(local && !target.dir
        ? [{ id: "default", label: "Open in default app", run: () => this.openWithDefault(target.path) }]
        : []),
      ...(local
        ? [{ id: "reveal", label: revealLabel(window()?.platform, ownFileManager()), run: () => this.reveal(target.path) }]
        : []),
    ]);
    if (!target.dir && target.changed && shared("better-files.has-changes"))
      groups.push([{ id: "diff", label: "Show diff", run: (cx) => this.showDiff(target, cx) }]);
    groups.push([
      {
        id: "copy-relative",
        label: "Copy relative path",
        run: (cx) => cx.write_to_clipboard(target.relative),
      },
      { id: "copy-path", label: "Copy full path", run: (cx) => cx.write_to_clipboard(target.path) },
    ]);
    const running = this.spaceAgents(this.menuSpace);
    groups.push([
      ...running.flatMap((a) => [
        {
          id: `agent-${a.address}`,
          label: `Send to ${agentName(a)}`,
          run: () => this.askForPrompt(target, a.address),
        },
        ...(this.spawnRun(a)
          ? [
              {
                id: `agent-spawn-${a.address}`,
                label: `Send to ${agentName(a)} (spawn)`,
                run: () => this.askForPrompt(target, `spawn:${a.address}`),
              },
            ]
          : []),
      ]),
      ...this.newAgentChoices().map((a) => ({
        id: `agent-${a.address}`,
        label: `Send to ${agentName(a)}`,
        run: () => this.askForPrompt(target, a.address),
      })),
    ]);
    return groups.filter((group) => group.length);
  },

  menuView() {
    const t = theme();
    const target = props()?.target ?? this.menuTarget;
    const view = v_flex()
      .id("files-menu")
      .w_full()
      .max_h(520)
      .overflow_y_scrollbar()
      .p(4)
      .rounded(7)
      .border_1()
      .border_color(t.border)
      .bg(t.popover)
      .text_color(t.foreground)
      .text_size(TEXT.tab);
    this.menuItems(target).forEach((group, i) => {
      if (i) view.child(div().h(1).my(3).flex_none().bg(t.border));
      for (const item of group)
        view.child(
          div()
            .id(`files-menu-${item.id}`)
            .flex_none()
            .h(24)
            .px(8)
            .flex()
            .items_center()
            .rounded(5)
            .cursor_pointer()
            .hover((s) => s.bg(t.hover))
            .on_click((_e, cx) => {
              item.run(cx);
              closeOverlay(props()?.overlay);
            })
            .child(div().truncate().child(item.label)),
        );
    });
    return view;
  },
};
