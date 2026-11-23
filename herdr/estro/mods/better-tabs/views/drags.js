// Dragging tabs and toolbar actions. GPUI gives pointer events, not a drag payload:
// the source keeps its slot, a copy follows the pointer, and a line shows where it
// would land. Nothing moves until release.
import { spaces, run, shared, setShared, closeOverlay, props } from "herdr";
import { duration } from "../settings.js";
import { hideToolbarAction, tabMoveIndex } from "../actions/toolbar.js";

export const DRAG_KEY = "better-tabs.action-drag";
export const DRAG_TIMEOUT_MS = 15000;
const DRAG_DELAY_MS = 400;
const DRAG_DISTANCE = 12; // A slow click can slip this far and still be a click.

const afterMiddle = (event) =>
  (event.local_position?.x ?? 0) > (event.bounds?.width ?? Infinity) / 2;

export const dragMethods = {
  beginTabDrag(tab, event, cx) {
    cx.stop_propagation();
    if (this.actionDrag()) setShared(DRAG_KEY, null);
    if (event.click_count === 2) {
      this.tabDrag = null;
      run("tab.rename", { id: tab.id });
      return;
    }
    const point = event.position ?? { x: 0, y: 0 };
    this.tabDrag = {
      id: tab.id,
      label: tab.name,
      space: spaces().find((s) => s.active)?.id,
      start: point,
      point,
      pressedAt: Date.now(),
      active: false,
      target: null,
    };
  },

  // A press has to last before it can drag, so a click that slips stays a click.
  dragReady(drag, point) {
    const delay = duration(this.settings.tabs.drag_delay, DRAG_DELAY_MS);
    const distance = Math.hypot(point.x - drag.start.x, point.y - drag.start.y);
    return Date.now() - drag.pressedAt >= delay && distance >= DRAG_DISTANCE;
  },

  hoverTab(tab, event, cx) {
    if (!this.tabDrag) return;
    const point = event.position ?? this.tabDrag.point;
    this.tabDrag.point = point;
    this.tabDrag.active ||= this.dragReady(this.tabDrag, point);
    if (this.tabDrag.active) {
      this.tabDrag.target = { id: tab.id, after: afterMiddle(event) };
      cx.notify();
    }
  },

  finishTabDrag(tab, event, cx) {
    const drag = this.tabDrag;
    if (!drag) return;
    cx.stop_propagation();
    this.hoverTab(tab, event, cx);
    this.commitTabDrag(cx, tab.id);
  },

  commitTabDrag(cx, clickedID = null) {
    const drag = this.tabDrag;
    this.tabDrag = null;
    if (!drag) return;
    const space = spaces().find((s) => s.active);
    if (space?.id === drag.space) {
      if (drag.active && drag.target) {
        const index = tabMoveIndex(space.tabs ?? [], drag.id, drag.target.id, drag.target.after);
        if (index !== null) run("tab.move", { id: drag.id, index });
        this.ignoreClickUntil = Date.now() + 300;
      } else if (!drag.active && drag.id === clickedID) run("tab.select", { id: clickedID });
    }
    cx.notify();
  },

  // Toolbar and popup instances exchange drag state through shared storage;
  // tab drags remain local because they never cross between those views.
  actionDrag() {
    const drag = shared(DRAG_KEY);
    return drag?.scope === this.toolbarScope() && Date.now() - drag.at < DRAG_TIMEOUT_MS
      ? drag
      : null;
  },

  beginActionDrag(entry, event, cx, fromMenu) {
    cx.stop_propagation();
    this.tabDrag = null;
    const point = event.position ?? { x: 0, y: 0 };
    setShared(DRAG_KEY, {
      scope: this.toolbarScope(),
      id: entry.id,
      label: entry.label ?? entry.id,
      icon: entry.icon,
      start: point,
      point,
      active: false,
      fromMenu,
      pressedAt: Date.now(),
      at: Date.now(),
      target: null,
    });
  },

  moveActionDrag(event, cx, target = undefined) {
    const drag = this.actionDrag();
    if (!drag) return;
    const point = event.position ?? drag.point;
    const active = drag.active || this.dragReady(drag, point);
    const next = { ...drag, point, active, at: Date.now() };
    if (target !== undefined) next.target = target;
    if (active) {
      setShared(DRAG_KEY, next);
      cx.notify();
    }
  },

  hoverAction(entry, event, cx) {
    this.moveActionDrag(event, cx, {
      kind: "toolbar",
      id: entry.id,
      after: afterMiddle(event),
      bounds: event.bounds,
    });
  },

  finishActionDrag(cx) {
    // A terminal tab dropped on an action is not a toolbar-action gesture.
    // Cancel it rather than leaving a ghost or activating the drop target.
    if (this.tabDrag) {
      this.tabDrag = null;
      this.ignoreClickUntil = Date.now() + 300;
      cx.notify();
      return true;
    }
    const drag = this.actionDrag();
    if (!drag) return false;
    setShared(DRAG_KEY, null);
    if (!drag.active) return false;
    // The click generated after a reorder must not also activate its button.
    this.ignoreClickUntil = Date.now() + 300;
    const entry = this.entries().find((item) => item.id === drag.id);
    if (entry && this.config().mode !== "overflow") {
      if (drag.target?.kind === "overflow")
        this.savePreferences(hideToolbarAction(this.preferences(), entry.id));
      else if (drag.target?.kind === "toolbar")
        this.pinAction(entry, drag.target.id, drag.target.after);
    }
    cx.notify();
    return true;
  },

  leaveMenu(_cx) {
    const drag = this.actionDrag();
    if (!drag?.fromMenu) return;
    // Closing the popup on drag-out exposes the real toolbar as a drop surface.
    setShared(DRAG_KEY, { ...drag, active: true, at: Date.now(), target: null });
    closeOverlay(props().overlay);
  },

  cancelDrags(cx) {
    const active = Boolean(this.tabDrag || this.actionDrag());
    this.tabDrag = null;
    if (this.actionDrag()) setShared(DRAG_KEY, null);
    if (active) cx.notify();
  },

  movePointer(event, cx) {
    if (event.bounds) this.barBounds = event.bounds;
    if (this.tabDrag) {
      const point = event.position ?? this.tabDrag.point;
      this.tabDrag.point = point;
      this.tabDrag.active ||= this.dragReady(this.tabDrag, point);
      if (this.tabDrag.active) cx.notify();
    }
    this.moveActionDrag(event, cx);
  },
};
