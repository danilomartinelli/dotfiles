// Which toolbar actions show, and in what order, saved per layout and toolbar.
import { shared, setShared, openOverlay } from "herdr";
import { toolbarPreferences, toolbarPartition, placeToolbarAction } from "../actions/toolbar.js";

const PREFERENCES_KEY = "better-tabs.toolbar";
// Each row is 32px, with 2px gaps and 5px padding on each edge.
const menuHeight = (count) => Math.min(420, Math.max(1, count) * 34 + 8);

export const arrangementMethods = {
  toolbarScope() {
    return this.config().toolbarScope ?? JSON.stringify([shared("layout") ?? "default", "main"]);
  },

  preferences() {
    return toolbarPreferences(shared(PREFERENCES_KEY)?.[this.toolbarScope()]);
  },

  savePreferences(value) {
    setShared(PREFERENCES_KEY, {
      ...(shared(PREFERENCES_KEY) ?? {}),
      [this.toolbarScope()]: value,
    });
  },

  toolbar() {
    const limit = Math.max(0, Math.floor(((this.width ?? 1200) - 350) / 100));
    return toolbarPartition(this.entries(), this.preferences(), limit);
  },

  pinAction(entry, target = null, after = false) {
    const entries =
      this.config().mode === "overflow"
        ? (this.config().allButtons ?? this.entries())
        : this.entries();
    this.savePreferences(placeToolbarAction(entries, this.preferences(), entry.id, target, after));
  },

  openActions(entries) {
    const bounds = this.moreBounds;
    // A popup is another copy of this mod. Pass its originating scope and full
    // action list so pinning can update the toolbar after the popup closes.
    openOverlay({
      ...(bounds
        ? {
            at: {
              x: Math.max(0, bounds.x + bounds.width - this.settings.menu.width),
              y: bounds.y + bounds.height + 6,
            },
          }
        : {}),
      mod: "better-tabs",
      kind: "popup",
      width: this.settings.menu.width,
      height: menuHeight(entries.length),
      props: {
        ...this.config(),
        mode: "overflow",
        toolbarScope: this.toolbarScope(),
        allButtons: this.entries(),
        buttons: entries,
        rememberPanels: false,
      },
    });
  },
};

export { menuHeight };
