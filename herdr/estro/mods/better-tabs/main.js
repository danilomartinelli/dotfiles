// Better Tabs: a tab bar with draggable tabs that wrap onto more lines, and a
// toolbar for panels with a ⋮ menu. A popup menu is another copy of this mod.
// The class is built from separate files:
//   views/panel-memory.js  which panel each space had open
//   views/arrangement.js   which toolbar actions show, saved per layout
//   views/drags.js         dragging tabs and toolbar actions
//   views/tab-bar.js       the bar: tabs, +, toolbar, ⋮
//   views/menu.js          the ⋮ menu and toolbar action buttons
//   actions/names.js       tabs named after what runs in them
// actions/ holds the logic with no drawing, views/ui.js the shared look.
import { View } from "gpui-kit";
import { shared, setShared, nextCommand, props, notify } from "herdr";
import { loadSettings } from "./settings.js";
import { buttons, execute } from "./actions/engine.js";
import { panelMemoryMethods } from "./views/panel-memory.js";
import { arrangementMethods } from "./views/arrangement.js";
import { dragMethods, DRAG_KEY, DRAG_TIMEOUT_MS } from "./views/drags.js";
import { tabBarMethods } from "./views/tab-bar.js";
import { menuMethods } from "./views/menu.js";
import { nameMethods } from "./actions/names.js";

// Preferences a person may change in the installed mod.json under `settings`.
const DEFAULT_SETTINGS = { tabs: { max_width: 170, drag_delay: "400ms", auto_name: true }, menu: { width: 240 } };

const DEFAULTS = {
  rememberPanels: { container: "panel", stack: "panel-body" },
  buttons: [
    {
      id: "files",
      label: "Files",
      icon: "file",
      when: { node: "files" },
      action: { type: "panel", container: "panel", stack: "panel-body", target: "files" },
    },
    {
      id: "changes",
      label: "Changes",
      icon: "changes",
      when: { node: "changes" },
      action: { type: "panel", container: "panel", stack: "panel-body", target: "changes" },
    },
  ],
};

class Tabs extends View {
  // ── Configuration, lifecycle, and command dispatch ────────────────────────

  config() {
    return { ...DEFAULTS, ...props() };
  }

  init(_props, cx) {
    this.settings = DEFAULT_SETTINGS;
    cx.spawn(async (cx) => {
      const { settings, problems } = await loadSettings("better-tabs", DEFAULT_SETTINGS);
      this.settings = settings;
      this.settingsReady = true;
      for (const problem of problems) console.warn(`better-tabs mod.json settings: ${problem}`);
      cx.notify();
    });
    this.tabDrag = null;
    this.swipe = { acc: 0, steps: 0, at: 0, last: 0 };
    this.panels = {};
    try {
      const saved = JSON.parse(localStorage.getItem("panels") ?? "{}");
      if (saved && typeof saved === "object" && !Array.isArray(saved)) this.panels = saved;
    } catch {
      /* Ignore malformed saved preferences. */
    }
    if (this.config().mode !== "overflow") {
      // Synchronization can issue layout commands, so it must not run in render.
      this.syncPanel();
      cx.timer.every(300, () => {
        this.syncPanel();
        this.nameTabs();
        const drag = shared(DRAG_KEY);
        if (drag?.scope === this.toolbarScope() && Date.now() - drag.at > DRAG_TIMEOUT_MS)
          setShared(DRAG_KEY, null);
      });
      cx.spawn(async (cx) => {
        for (;;) this.command(await nextCommand());
      });
    }
  }

  entries() {
    return buttons(this.config());
  }

  command(command) {
    if (command === "overflow") return this.openActions(this.toolbar().overflow);
    if (!command.startsWith("button:")) return;
    const entry = this.entries().find((button) => button.id === command.slice(7));
    if (entry) this.act(entry.action);
  }

  act(action) {
    try {
      execute(action);
    } catch (error) {
      notify({ title: "Better Tabs", body: String(error.message ?? error), level: "error" });
    }
  }
}

Object.assign(
  Tabs.prototype,
  panelMemoryMethods,
  arrangementMethods,
  dragMethods,
  tabBarMethods,
  menuMethods,
  nameMethods,
);

export default Tabs;
