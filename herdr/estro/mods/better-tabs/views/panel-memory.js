// Which panel each space had open, restored when you return to the space.
import { spaces, run, layout } from "herdr";
import { find } from "../actions/engine.js";

export const panelMemoryMethods = {
  // ── Per-space panel memory ───────────────────────────────────────────────

  syncPanel() {
    const memory = this.config().rememberPanels;
    if (!memory) return;
    const space = spaces().find((s) => s.active);
    const root = layout();
    const panel = find(root, memory.container);
    const body = find(root, memory.stack);
    if (!space || !panel || !body) return;
    const key = JSON.stringify([memory.container, memory.stack, space.id]);
    const now = panel.hidden ? null : body.active;
    if (key !== this.spaceKey) {
      const first = this.spaceKey === undefined;
      this.spaceKey = key;
      this.pending = null;
      if (!(first && !Object.prototype.hasOwnProperty.call(this.panels, key))) {
        const stored = this.panels[key];
        const want = body.children?.some((c) => c.id === stored) ? stored : null;
        if (want !== now) {
          this.pending = { want, until: Date.now() + 1000 };
          if (want) {
            run("layout.select", { stack: memory.stack, child: want });
            run("layout.show", { id: memory.container });
          } else run("layout.hide", { id: memory.container });
          return;
        }
      }
    }
    // Commands are queued. Let a restore reach the layout before saving again,
    // or the old visible panel would overwrite the preference we just restored.
    if (this.pending) {
      if (this.pending.want !== now && Date.now() < this.pending.until) return;
      this.pending = null;
    }
    if (this.panels[key] === now) return;
    this.panels[key] = now;
    localStorage.setItem("panels", JSON.stringify(this.panels));
  },
};
