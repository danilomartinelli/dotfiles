// Toolbar action buttons, and the ⋮ menu that lists the hidden ones with a pin.
import { div } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { theme, setShared, closeOverlay, props } from "herdr";
import { isActive } from "../actions/engine.js";
import { menuHeight } from "./arrangement.js";
import { DRAG_KEY } from "./drags.js";
import { TEXT, Icon, DropLine } from "./ui.js";

export const menuMethods = {
  actionButton(entry, menu = false) {
    const t = theme();
    const drag = this.actionDrag();
    const active = isActive(entry.action);
    const label = entry.label ?? entry.id;
    const tooltip = entry.tooltip ?? label;
    const dropHere =
      !menu && drag?.active && drag.target?.kind === "toolbar" && drag.target.id === entry.id;
    const button = h_flex()
      .id(`action-${entry.id}`)
      .relative()
      .h(menu ? 32 : 26)
      .px(8)
      .gap(5)
      .flex_none()
      .items_center()
      .rounded(6)
      .when(menu, (el) => el.w_full())
      .text_size(menu ? TEXT.menu : TEXT.button)
      .bg(active ? t.selected : menu ? t.popover : t.chrome)
      .text_color(active ? t.foreground : t.muted)
      .tooltip(menu ? `${tooltip} · Drag out or pin to show in toolbar` : tooltip)
      .accessibility_label(label)
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .when(drag?.active && drag.id === entry.id && !menu, (el) => el.opacity(0.35))
      .when(Boolean(entry.icon), (el) => el.child(Icon(entry.icon)))
      .child(
        div()
          .when(menu, (el) => el.flex_1().min_w(0).truncate())
          .child(label),
      )
      .when(dropHere, (el) => el.child(DropLine(drag.target.after)))
      .when(menu, (el) => el.child(this.pinButton(entry)));
    return this.withActionEvents(button, entry, menu);
  },

  withActionEvents(button, entry, menu) {
    return button
      .on_mouse_down("left", (event, cx) => this.beginActionDrag(entry, event, cx, menu))
      .on_mouse_move((event, cx) => {
        if (menu) this.moveActionDrag(event, cx);
        else this.hoverAction(entry, event, cx);
      })
      .on_mouse_up("left", (_event, cx) => {
        cx.stop_propagation();
        this.finishActionDrag(cx);
      })
      .on_click((_e, cx) => {
        cx.stop_propagation();
        // A click can arrive without the release handler above having run, and a
        // drag left open would then stick to the pointer.
        this.finishActionDrag(cx);
        if (Date.now() < this.ignoreClickUntil) return;
        if (menu) closeOverlay(props().overlay);
        this.act(entry.action);
      });
  },

  pinButton(entry) {
    return this.simple(`pin-${entry.id}`, Icon("pin", 13), "Show in toolbar", () => {
      setShared(DRAG_KEY, null);
      this.pinAction(entry);
      closeOverlay(props().overlay);
    })
      .size(22)
      .on_mouse_up("left", (_e, cx) => cx.stop_propagation());
  },

  renderOverflow() {
    const t = theme();
    const entries = this.entries()
      .slice()
      .sort(
        (a, b) =>
          String(a.label ?? a.id).localeCompare(String(b.label ?? b.id), undefined, {
            sensitivity: "base",
          }) || a.id.localeCompare(b.id),
      );
    // A scroll container has no intrinsic content height in a native popup.
    // Give the popup a real size, then scroll only its flexing inner list.
    const list = v_flex().id("actions-menu-list").flex_1().min_h(0).gap(2).overflow_y_scrollbar();
    if (!entries.length)
      list.child(
        h_flex()
          .h(32)
          .flex_none()
          .px(8)
          .items_center()
          .text_size(TEXT.menu)
          .text_color(t.dim)
          .tooltip("Drag a toolbar action onto ⋮ to hide it here.")
          .child("No hidden actions"),
      );
    list.children(entries.map((entry) => this.actionButton(entry, true)));
    return v_flex()
      .id("actions-menu")
      .w(this.settings.menu.width)
      .h(menuHeight(entries.length))
      .p(5)
      .text_color(t.foreground)
      .bg(t.popover)
      .on_hover((hovered, cx) => {
        if (!hovered) this.leaveMenu(cx);
      })
      .on_mouse_down_out((_event, cx) => this.cancelDrags(cx))
      .child(list);
  },
};
