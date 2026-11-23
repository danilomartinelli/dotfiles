// The bar: tabs that wrap onto more lines, the + after them, then the toolbar and ⋮.
import { div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, run, openOverlay, theme, window, shared, layout, settings } from "herdr";
import { find } from "../actions/engine.js";
import { TEXT, Icon, IconButton, DropLine } from "./ui.js";

const CHAR_WIDTH = 8; // Roughly, to size the drag preview.
const TAB_HEIGHT = 29;
const TAB_GAP = 6; // Wide enough for the drop line to stand clear of both tabs.
const BAR_HEIGHT = 42;
const BAR_PADDING = BAR_HEIGHT - TAB_HEIGHT;

const contains = (bounds, point) =>
  bounds &&
  point.x >= bounds.x &&
  point.x <= bounds.x + bounds.width &&
  point.y >= bounds.y &&
  point.y <= bounds.y + bounds.height;

export const tabBarMethods = {
  // A small button that ignores the click a drag's release can leave behind.
  simple(id, content, label, action) {
    return IconButton({
      id,
      content,
      label,
      onClick: (event, cx) => {
        if (!(Date.now() < this.ignoreClickUntil)) action(event, cx);
      },
    });
  },

  tabIcon(tab, ps, t) {
    const mine = ps.filter((p) => p.tab === tab.id);
    const draw = (pic) =>
      pic?.icon ? (pic.tint ? svg(pic.icon).size(14).text_color(t.muted) : image(pic.icon).size(14)) : null;
    // A program pane leads, picked the way Better Sidebar's lead() picks it: an agent, else the
    // focused one, else the first. So both show the same icon for a tab.
    const progs = mine.filter((p) => !p.mod);
    const program = (progs.find((p) => p.program?.agent) ?? progs.find((p) => p.focused) ?? progs[0])?.program;
    if (program?.icon) return draw(program);
    // Mod panes carry no program. Any of them may publish its own icon in shared("pane-heads"), as
    // a Better Files or Better Changes tab does for its file, with color: true for a full-colour
    // picture; else the mod may publish an icon for itself.
    const heads = shared("pane-heads") ?? {};
    const head = heads[mine.find((p) => p.mod && heads[p.pane]?.icon)?.pane];
    if (head) return draw({ icon: head.icon, tint: !head.color });
    return draw({ icon: shared("mod-icons")?.[mine.find((p) => p.mod)?.mod], tint: true });
  },

  // Smooth touchpad gestures can emit many small events. Accumulate them into
  // one tab step at a time, while a wheel notch switches immediately.
  wheelTabs(event) {
    if (event.delta_lines) {
      if (event.delta_lines.y) run(event.delta_lines.y > 0 ? "tab.prev" : "tab.next");
      return;
    }
    const swipe = this.swipe;
    const now = Date.now();
    if (
      event.touch_phase === "started" ||
      now - swipe.at > 250 ||
      event.delta.y * swipe.acc < 0
    )
      Object.assign(swipe, { acc: 0, steps: 0 });
    swipe.at = now;
    swipe.acc += event.delta.y;
    const step = swipe.steps ? 60 : 20;
    if (Math.abs(swipe.acc) < step || now - swipe.last < 100) return;
    swipe.acc -= Math.sign(swipe.acc) * step;
    swipe.steps++;
    swipe.last = now;
    run(event.delta.y > 0 ? "tab.prev" : "tab.next");
  },

  tabItem(tab, space, ps, t) {
    const icon = this.tabIcon(tab, ps, t);
    const drag = this.tabDrag;
    return h_flex()
      .id(`tab-${tab.id}`)
      .relative()
      .h(TAB_HEIGHT)
      .px(10)
      .gap(7)
      .rounded(7)
      .items_center()
      .flex_none()
      .text_size(TEXT.tab)
      .border(1)
      .border_color(tab.active ? t.border : t.chrome)
      .bg(tab.active ? t.raised : t.chrome)
      .text_color(tab.active ? t.foreground : t.muted)
      .hover((s) => s.bg(t.hover))
      .when(drag?.active && drag.id === tab.id, (el) => el.opacity(0.35))
      .on_mouse_down("left", (event, cx) => this.beginTabDrag(tab, event, cx))
      .on_mouse_move((event, cx) => this.hoverTab(tab, event, cx))
      .on_mouse_up("left", (event, cx) => this.finishTabDrag(tab, event, cx))
      .on_mouse_down("right", (_e, cx) => {
        cx.stop_propagation();
        this.cancelDrags(cx);
        openOverlay({
          mod: "menu",
          kind: "popup",
          width: 200,
          props: { tab: "tab", target: { id: tab.id, space: space.id } },
        });
      })
      .when(Boolean(icon), (el) => el.child(icon))
      .child(
        div()
          .max_w(this.settings.tabs.max_width)
          .truncate()
          .tooltip(tab.name)
          .child(tab.zoomed ? `${tab.name} Z` : tab.name),
      )
      .when(tab.status === "working", (el) =>
        el.child(Icon("spinner", 12).text_color(t.working).spin(900)),
      )
      .when(["blocked", "done"].includes(tab.status), (el) =>
        el.child(div().size(6).rounded(3).bg(t[tab.status])),
      )
      .when(tab.active, (el) => el.child(this.closeTabButton(tab)))
      .when(drag?.active && drag.target?.id === tab.id, (el) =>
        el.child(DropLine(drag.target.after)),
      );
  },

  closeTabButton(tab) {
    return this.simple(`close-${tab.id}`, Icon("close", 12), "Close tab", (_e, cx) => {
      this.cancelDrags(cx);
      run("tab.close", { id: tab.id });
    }).on_mouse_up("left", (_e, cx) => cx.stop_propagation());
  },

  dragPreview(t) {
    const drag = this.tabDrag?.active ? this.tabDrag : this.actionDrag();
    if (!drag?.active) return null;
    const width = Math.min(
      200,
      Math.max(90, String(drag.label).length * CHAR_WIDTH + (drag.icon ? 52 : 32)),
    );
    const x = drag.point.x - (this.barBounds?.x ?? 0);
    // Offset the preview from the pointer so it cannot cover the drop hitbox.
    const left = x + width + 12 < (this.width ?? 1200) ? x + 12 : Math.max(0, x - width - 12);
    return h_flex()
      .id("drag-preview")
      .absolute()
      .left(left)
      .top(4)
      .h(29)
      .w(width)
      .px(9)
      .gap(5)
      .items_center()
      .rounded(7)
      .border(1)
      .border_color(t.accent)
      .bg(t.raised)
      .text_color(t.foreground)
      .opacity(0.95)
      .when(Boolean(drag.icon), (el) => el.child(Icon(drag.icon)))
      .child(div().min_w(0).truncate().child(drag.label));
  },

  // Tabs wrap, and only the layout can make the bar taller. Sizes reach us scaled by
  // zoom, while layout sizes are written as at zoom 1.
  fitHeight(size) {
    const rows = Math.round(size.height / (settings().zoom || 1));
    const height = Math.max(BAR_HEIGHT, rows + BAR_PADDING);
    if (height === this.barHeight) return;
    this.barHeight = height;
    run("layout.resize", { id: find(layout(), "tabs-row") ? "tabs-row" : "tabs", px: height });
  },

  // Room for the macOS traffic lights when the sidebar doesn't already clear them.
  leftPadding() {
    const root = layout();
    const w = window();
    if (w?.platform !== "macos" || w.titlebar !== "none" || w.fullscreen || !root?.traffic_lights)
      return 10;
    const sidebar = find(root, "sidebar");
    const lights = (root.traffic_lights[0] + 64) / (settings().zoom || 1);
    return Math.max(10, lights - (sidebar?.hidden ? 0 : (sidebar?.size?.px ?? 0)));
  },

  render() {
    if (this.config().mode === "overflow") return this.renderOverflow();
    const t = theme();
    const bar = h_flex()
      .id("better-tabs-root")
      .relative()
      .text_size(TEXT.tab)
      .size_full()
      .min_w(0)
      .px(10)
      .pl(this.leftPadding())
      .pt(BAR_PADDING / 2)
      .gap(TAB_GAP)
      .items_start()
      .bg(t.chrome)
      .border_b(1)
      .border_color(t.border)
      .on_size_change((size, cx) => {
        if (this.width !== size.width) {
          this.width = size.width;
          cx.notify();
        }
      })
      .on_mouse_move((event, cx) => this.movePointer(event, cx))
      .on_scroll_wheel((event) => this.wheelTabs(event))
      .on_mouse_up("left", (_event, cx) => {
        this.commitTabDrag(cx);
        this.finishActionDrag(cx);
      })
      .on_mouse_down_out((_event, cx) => this.cancelDrags(cx))
      .on_hover((hovered, cx) => {
        if (!hovered) this.cancelDrags(cx);
      })
      .child(this.renderTabList(t))
      .child(this.renderToolbar(t));
    if (window()?.buttons) bar.children(this.windowButtons());
    const preview = this.dragPreview(t);
    if (preview) bar.child(preview);
    return bar;
  },

  renderTabList(t) {
    const space = spaces().find((s) => s.active);
    const tabs = space?.tabs ?? [];
    const ps = panes();
    return h_flex()
      .id("tab-scroll")
      .flex_1()
      .min_w(0)
      .flex_wrap()
      .items_center()
      .gap(TAB_GAP)
      .on_size_change((size) => this.fitHeight(size))
      .children(tabs.map((tab) => this.tabItem(tab, space, ps, t)))
      .child(this.newTabButton(tabs));
  },

  // Dropping a tab on the + puts it last.
  newTabButton(tabs) {
    const asLast = (event) => ({ ...event, local_position: { x: Infinity } });
    return this.simple("tab-new", Icon("plus", 14), "New tab", () =>
      openOverlay({ mod: "new-menu", kind: "popup", width: 250, height: 512 }),
    )
      .on_mouse_move((event, cx) => {
        if (tabs.length) this.hoverTab(tabs.at(-1), asLast(event), cx);
      })
      .on_mouse_up("left", (event, cx) => {
        if (this.tabDrag && tabs.length) this.finishTabDrag(tabs.at(-1), asLast(event), cx);
      });
  },

  renderToolbar(t) {
    const { visible, overflow } = this.toolbar();
    const toolbar = h_flex()
      .id("action-toolbar")
      .h(TAB_HEIGHT)
      .gap(TAB_GAP)
      .items_center()
      .flex_none()
      .on_mouse_move((event, cx) => {
        const drag = this.actionDrag();
        if (!drag || contains(drag.target?.bounds, event.position ?? drag.point)) return;
        this.moveActionDrag(event, cx, {
          kind: "toolbar",
          id: visible.at(-1)?.id ?? null,
          after: true,
          bounds: event.bounds,
        });
      })
      .on_hover((hovered, cx) => {
        if (!hovered && this.actionDrag()?.target) this.moveActionDrag({}, cx, null);
      });
    let group;
    for (const entry of visible) {
      if (group !== undefined && entry.group !== group)
        toolbar.child(div().w(1).h(16).mx(4).bg(t.border));
      group = entry.group;
      toolbar.child(this.actionButton(entry));
    }
    return toolbar.child(this.moreButton(overflow, t));
  },

  // The ⋮: lists hidden actions, and takes a dragged action to hide it.
  moreButton(overflow, t) {
    const drag = this.actionDrag();
    return this.simple(
      "actions-more",
      Icon("more-vertical", 16),
      "More actions · drop a toolbar action here to hide it",
      () => this.openActions(overflow),
    )
      .when(drag?.active && drag.target?.kind === "overflow", (el) =>
        el.bg(t.selected).border(1).border_color(t.accent),
      )
      .on_mouse_down("left", (event, cx) => {
        cx.stop_propagation();
        this.moreBounds = event.bounds ?? this.moreBounds;
      })
      .on_mouse_move((event, cx) => {
        this.moreBounds = event.bounds ?? this.moreBounds;
        this.moveActionDrag(event, cx, { kind: "overflow", bounds: event.bounds });
      })
      .on_mouse_up("left", (_event, cx) => {
        cx.stop_propagation();
        this.finishActionDrag(cx);
      });
  },

  // Windows and Linux draw their own window controls.
  windowButtons() {
    const w = window();
    const windows = w.platform === "windows";
    return [
      this.simple("minimize", windows ? Icon("win-min", 16) : "−", "Minimize", () =>
        run("window.minimize"),
      ),
      this.simple(
        "maximize",
        windows ? Icon(w.maximized ? "win-restore" : "win-max", 16) : "□",
        "Maximize",
        () => run("window.maximize"),
      ),
      this.simple("close-window", Icon("close", 13), "Close window", () => run("window.close")),
    ];
  },
};
