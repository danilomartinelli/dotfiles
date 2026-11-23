// The header row above each pane, as Herdr's own `pane` mod draws it, with one
// addition: a Better Changes diff shows the file instead of the mod's name.
// A layout turns it on with { "header": { "content": { "mod": "better-changes" } } }.
import { div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { panes, props, run, theme, home, shared } from "herdr";

function programIcon(program, size, color) {
  if (!program?.icon) return null;
  if (program.tint) return svg(program.icon).size(size).flex_none().text_color(color);
  return image(program.icon).w(size).h(size).flex_none();
}

function shortFolder(cwd) {
  if (!cwd) return "";
  const homeFolder = home();
  if (cwd === homeFolder) return "~";
  return cwd.startsWith(`${homeFolder}/`) ? `~${cwd.slice(homeFolder.length)}` : cwd;
}

export const paneHeaderMethods = {
  paneButton(t, id, icon, command, args) {
    return div()
      .id(id)
      .p(3)
      .rounded(4)
      .text_color(t.dim)
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => {
        cx.stop_propagation();
        run(command, args);
      })
      .child(svg(`mods/better-changes/icons/${icon}.svg`).size(14));
  },

  renderPaneHeader() {
    const t = theme();
    const p = panes().find((candidate) => candidate.pane === props()?.pane);
    if (!p) return div();

    const isProgram = p.program?.agent || p.program?.shell;
    const name = (isProgram && p.program.name) || p.title || p.program?.name || "shell";
    const head = shared("pane-heads")?.[p.pane];
    const pic = head?.icon
      ? head.color
        ? image(head.icon).size(14).flex_none()
        : svg(head.icon).size(14).flex_none().text_color(t.dim)
      : programIcon(p.program, 14, t.dim);
    const pane = p.pane;

    return h_flex()
      .id(`pane-head-${pane}`)
      .size_full()
      .px(10)
      .gap(8)
      .items_center()
      .bg(t.background)
      .border_b(1)
      .border_color(t.border)
      .text_size(12)
      .on_hover((hovered, cx) => {
        this.hovered = hovered;
        cx.notify();
      })
      .on_click(() => run("pane.focus", { pane }))
      .when(Boolean(pic), (el) => el.child(pic))
      .child(
        div()
          .flex_none()
          .truncate()
          .max_w(260)
          .font_medium()
          .text_color(t.foreground)
          .child(head?.title ?? name),
      )
      .child(
        div()
          .flex_1()
          .truncate()
          .text_color(t.dim)
          .child(head?.detail ?? shortFolder(p.cwd)),
      )
      .when(head?.add > 0, (el) =>
        el.child(div().flex_none().text_color(t.ansi2).child(`+${head.add}`)),
      )
      .when(head?.del > 0, (el) =>
        el.child(div().flex_none().text_color(t.ansi1).child(`−${head.del}`)),
      )
      .when(p.status === "working", (el) =>
        el.child(
          svg("mods/workspace-chrome/spinner.svg")
            .size(12)
            .flex_none()
            .text_color(t.working)
            .spin(900),
        ),
      )
      .when(p.status === "blocked", (el) =>
        el.child(
          div()
            .flex_none()
            .px(6)
            .h(18)
            .flex()
            .items_center()
            .rounded(5)
            .bg(`${t.blocked}26`)
            .text_size(10.5)
            .font_semibold()
            .text_color(t.blocked)
            .child("Needs you"),
        ),
      )
      .when(p.status === "done", (el) => el.child(div().size(7).flex_none().rounded(4).bg(t.done)))
      .when(Boolean(this.hovered), (el) =>
        el
          .when(p.mod === "better-changes", (el) => el.child(this.FullFileButton()))
          .child(
            this.paneButton(t, `ph-r-${pane}`, "split-right", "pane.split", {
              direction: "right",
              pane,
            }),
          )
          .child(
            this.paneButton(t, `ph-d-${pane}`, "split-down", "pane.split", {
              direction: "down",
              pane,
            }),
          )
          .child(
            this.paneButton(t, `ph-z-${pane}`, p.zoomed ? "unzoom" : "zoom", "pane.zoom", { pane }),
          )
          .child(this.paneButton(t, `ph-x-${pane}`, "close", "pane.close", { pane })),
      );
  },
};
