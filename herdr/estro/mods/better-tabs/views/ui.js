// The design kit: Herdr's own conventions as tokens and small components, with
// only what this mod uses. Components return ordinary elements, so callers can chain.
import { div, svg } from "gpui-kit";
import { theme } from "herdr";

// Plain px: Herdr scales a mod's sizes by zoom itself.
export const TEXT = { button: 12, menu: 12.8, tab: 12.8 };

// A bundled icon's name, or the path of another mod's.
export const Icon = (name, size = 14) =>
  svg(name.includes("/") ? name : `mods/better-tabs/icons/${name}.svg`)
    .size(size)
    .flex_none();

export function IconButton({ id, content, label, onClick }) {
  const t = theme();
  return div()
    .id(id)
    .size(26)
    .flex_none()
    .flex()
    .items_center()
    .justify_center()
    .rounded(6)
    .text_color(t.dim)
    .tooltip(label)
    .accessibility_label(label)
    .hover((s) => s.bg(t.hover).text_color(t.foreground))
    .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
    .on_click((event, cx) => {
      cx.stop_propagation();
      onClick(event, cx);
    })
    .child(content);
}

// Where a dragged tab would land: its own line in the gap between two tabs,
// clear of their borders.
export function DropLine(after) {
  const t = theme();
  return div()
    .id("drop-indicator")
    .absolute()
    .top(2)
    .bottom(2)
    .w(2)
    .rounded(1)
    .bg(t.accent)
    .when(after, (el) => el.right(-4))
    .when(!after, (el) => el.left(-4));
}
