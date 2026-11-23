// Opening a file in the centre: one shared tab per space for browsing, and tabs you keep.
// Every viewer has an ID in a shared registry, because a copy of a mod can't name its own
// tab: it records the tab it was opened in, and the sidebar and menus act through that.
import { panes, run, shared, setShared, spaces } from "herdr";
import { baseName } from "../files/model.js";

const VIEWERS = "better-files.viewers";
const OPENING_MS = 1500;
const PRUNE_AFTER_MS = 15000;

export const viewerEntries = () => shared(VIEWERS) ?? {};

export const openMethods = {
  setViewer(id, change) {
    const entries = viewerEntries();
    setShared(VIEWERS, { ...entries, [id]: { ...entries[id], ...change } });
  },

  tabIsLive(tab) {
    return panes().some((p) => p.tab === tab && p.mod === "better-files");
  },

  viewerIsLive(entry) {
    return entry.tab ? this.tabIsLive(entry.tab) : Date.now() - (entry.at ?? 0) < OPENING_MS;
  },

  // Which space each tab is in, from one look at the spaces.
  tabSpaces() {
    return new Map(spaces().flatMap((s) => (s.tabs ?? []).map((t) => [t.id, s.id])));
  },

  // Whether a viewer's recorded tab is listed in another space. Focus can sit in another
  // space while a viewer opens, and a click selecting that tab would make Herdr switch
  // spaces, so it isn't the viewer's: the viewer looks for its own, and that tab's own viewer
  // can claim it. Only a tab listed elsewhere counts: one not listed yet, as while tabs come
  // back after a restart, is left alone.
  wrongTab(entry, where = this.tabSpaces()) {
    return Boolean(entry.tab) && (where.get(entry.tab) ?? entry.space) !== entry.space;
  },

  liveViewers(space) {
    const where = this.tabSpaces();
    return Object.entries(viewerEntries()).filter(
      ([, entry]) => entry.space === space && this.viewerIsLive(entry) && !this.wrongTab(entry, where),
    );
  },

  // Tabs that have closed take their entries with them. Not at first: after a restart the
  // tabs come back a moment after this runs, and would lose their place in the registry,
  // so a click would open a file again that's already open.
  pruneViewers() {
    if (Date.now() - this.startedAt < PRUNE_AFTER_MS) return;
    const entries = viewerEntries();
    const live = Object.entries(entries).filter(([, entry]) => this.viewerIsLive(entry));
    if (live.length !== Object.keys(entries).length) setShared(VIEWERS, Object.fromEntries(live));
  },

  newViewer(file, space, preview) {
    const id = `v${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
    // Tabs that aren't this one, so it can tell its own when it opens.
    const others = panes()
      .filter((p) => p.mod === "better-files")
      .map((p) => p.tab);
    this.setViewer(id, { space, file, preview, tab: null, others, at: Date.now() });
    run("tab.new", {
      space,
      name: baseName(file.path),
      mod: "better-files",
      props: { mode: "viewer", viewer: id, space, file },
    });
    return id;
  },

  // A click: already open goes to that tab, otherwise it's shown in the shared one.
  openFile(file, cx) {
    const space = spaces().find((s) => s.active)?.id;
    if (!space) return;
    const viewers = this.liveViewers(space);
    const open = viewers.find(([, entry]) => entry.file?.path === file.path);
    if (open) {
      if (open[1].tab) run("tab.select", { id: open[1].tab });
    } else {
      const shared_ = viewers.find(([, entry]) => entry.preview);
      if (shared_) {
        const [id, entry] = shared_;
        this.setViewer(id, { file });
        if (entry.tab) {
          run("tab.rename", { id: entry.tab, name: baseName(file.path) });
          run("tab.select", { id: entry.tab });
        }
      } else this.newViewer(file, space, true);
    }
    cx?.notify();
  },

  // A double-click: the shared tab holding this file becomes one you keep, and the next
  // click starts a new shared tab. A double-click has already been a click, so it never
  // needs a second tab of its own.
  keepFile(file, cx) {
    const space = spaces().find((s) => s.active)?.id;
    const open = this.liveViewers(space).find(([, entry]) => entry.file?.path === file.path);
    if (open) this.setViewer(open[0], { preview: false });
    cx?.notify();
  },

  // From the menu: always a tab of its own.
  openInNewTab(file, cx) {
    const space = spaces().find((s) => s.active)?.id;
    if (!space) return;
    const open = this.liveViewers(space).find(([, entry]) => entry.file?.path === file.path);
    if (open) {
      this.setViewer(open[0], { preview: false });
      if (open[1].tab) run("tab.select", { id: open[1].tab });
    } else this.newViewer(file, space, false);
    cx?.notify();
  },

  // Hands a changed file to Better Changes, the way its own list does. `top` is the Git
  // root, which is what it knows a file by.
  showDiff(target, cx) {
    const space = spaces().find((s) => s.active);
    if (!space || !target.top) return;
    const source = { cwd: target.top, on: target.on ?? null };
    const selection = {
      context: JSON.stringify(source),
      root: target.top,
      on: target.on ?? null,
      path: target.relative,
      scope: target.staged ? "staged" : "unstaged",
      at: Date.now(),
    };
    const entries = shared("better-changes.diff-tabs") ?? {};
    const ids = new Set((space.tabs ?? []).map((t) => t.id));
    const tab = panes().find((p) => p.mod === "better-changes" && ids.has(p.tab))?.tab;
    const name = baseName(target.path);
    setShared("better-changes.selection", selection);
    setShared("better-changes.diff-tabs", {
      ...entries,
      [space.id]: { source, selection, pending: tab ? null : Date.now() },
    });
    if (tab) {
      run("tab.rename", { id: tab, name });
      run("tab.select", { id: tab });
    } else
      run("tab.new", {
        space: space.id,
        name,
        mod: "better-changes",
        props: { mode: "diff", space: space.id, source, selection },
      });
    cx?.notify();
  },
};
