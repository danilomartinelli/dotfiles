// Better Files: a read-only file browser. One class plays three roles, each its own copy:
//   the sidebar        the tree, and the box for a prompt to an agent
//   a viewer           a file in a centre tab
//   the menu           a popup at the pointer on right-click
// shared("better-files.*") connects them. The class is built from:
//   files/reads.js        the folder tree and Git's view of it
//   files/file-icons.js   Better Icons' pictures, when it's installed
//   files/filter.js       what the filter matches, from a list of every file
//   actions/open.js       opening tabs, and handing a file to Better Changes
//   actions/outside.js    code editors, Finder/Explorer/the file manager
//   actions/agents.js     sending a file to an agent
//   actions/menus.js      popup menus
//   views/tree.js, filter.js, tools.js, viewer.js, context-menu.js   the drawing
//   views/keys.js         the tree from the keyboard
// files/model.js says what the data means; views/ui.js holds every look but the token
// colours: syntax.js colours the file view's code, and Better Changes has the same file.
import { View } from "gpui-kit";
import { InputState, ScrollHandle, TextareaState } from "gpui-base";
import { appHome, checking, exec, nextCommand, props, setShared, shared, spaces, window } from "herdr";
import { loadSettings, duration } from "./settings.js";
import { followFileIcons } from "./files/file-icons.js";
import { readMethods } from "./files/reads.js";
import { pickCleanupListing } from "./files/shell.js";
import { openMethods } from "./actions/open.js";
import { outsideMethods } from "./actions/outside.js";
import { agentMethods } from "./actions/agents.js";
import { menuMethods } from "./actions/menus.js";
import { treeMethods } from "./views/tree.js";
import { filterMethods } from "./views/filter.js";
import { savedDotfiles, toolMethods } from "./views/tools.js";
import { keyMethods } from "./views/keys.js";
import { viewerMethods } from "./views/viewer.js";
import { contextMenuMethods } from "./views/context-menu.js";

const DEFAULT_SETTINGS = { refresh: { tree: "10s", file: "2s" }, editors: [], fileManager: { name: "", command: [] }, gutter: true, markdown: "preview" };
const SYNC_MS = 300;
const CLEANUP_KEY = "better-files.cleanup";
const CLEANUP_OVERFLOW = "better-files.cleanupOverflow";
const CLEANUP_GENERATION = "better-files.cleanupGeneration";
const CLEANUP_LIMIT = 256;
const CLEANUP_DELAY_MS = 10000;
const CLEANUP_BATCH = 32;
const CACHE_COPY = /^mods\/better-files\/\.cache\/[a-zA-Z0-9_-]+\.[a-zA-Z0-9]+$/;
const SWEEP_COPY = /^v[a-z0-9]+(?:-m\d+)?-(?:\d+|[0-9a-f]{16})-\d+\.(?:png|jpe?g|gif|webp|bmp|svg)(?:\.part)?$/i;
let cleanupWorker = null;
const cacheOwners = new Set();
const cleanupProtectedOwners = new Set();

class BetterFiles extends View {
  init(given, cx) {
    const p = props() ?? given ?? {};
    this.mode = p.mode ?? "sidebar";
    if (this.mode === "menu") {
      this.menuTarget = p.target;
      this.menuSpace = spaces().find((s) => s.active)?.id;
      return;
    }
    if (checking()) {
      if (this.mode === "sidebar") this.initSidebar(cx, true);
      return;
    }
    this.menuFocus = cx.focus_handle();
    // Better Tabs draws this on a file's tab.
    setShared("mod-icons", {
      ...(shared("mod-icons") ?? {}),
      "better-files": "mods/better-files/icons/file.svg",
    });
    followFileIcons(this, cx);
    if (this.mode === "viewer") return this.initViewer(p, cx);
    this.initSidebar(cx);
  }

  initViewer(p, cx) {
    this.viewerId = p.viewer;
    if (this.viewerId) cacheOwners.add(this.viewerId);
    this.viewerSpace = p.space;
    this.viewerFile = p.file;
    this.gutterOn = true;
    this.markdownDefault = DEFAULT_SETTINGS.markdown;
    this.hunks = [];
    this.openHunks = new Set();
    // The preview's position, so an `#anchor` link can scroll it. A handle must be made here.
    this.previewScroll = ScrollHandle.new();
    this.syncViewer(cx);
    cx.timer.every(SYNC_MS, (cx) => this.syncViewer(cx));
    cx.spawn(async (cx) => {
      const { settings } = await loadSettings("better-files", DEFAULT_SETTINGS);
      this.markdownDefault = settings.markdown === "code" ? "code" : "preview";
      cx.notify();
      // Folding can't change once a view is made, so turning the gutter off starts a new one.
      if (settings.gutter === false) {
        this.gutterOn = false;
        this.hunks = [];
        this.code?.release();
        this.code = null;
        this.text = undefined;
        this.readFile(cx);
      }
      cx.timer.every(Math.max(500, duration(settings.refresh.file, 2000)), (cx) => {
        this.readFile(cx);
        this.readHunks(cx);
      });
    });
  }

  initSidebar(cx, checkingOnly = false) {
    this.startedAt = Date.now();
    this.saved = new Map();
    this.entries = new Map();
    this.folders = new Set();
    this.marks = {};
    this.editor = TextareaState.new({ placeholder: "What should it do with this?", rows: 3 });
    this.editor.on("change", (_e, cx) => cx.notify());
    this.filter = InputState.new({ placeholder: "Filter files" });
    this.filter.on("change", (_e, cx) => {
      // New words, new matches: the arrows start again from the top.
      this.cursor = null;
      this.ensureIndex(cx);
      cx.notify();
    });
    this.filter.on("submit", (_e, cx) => this.openFirstMatch(cx));
    this.filter.on("focus", (_e, cx) => {
      this.filterFocused = true;
      cx.notify();
    });
    this.filter.on("blur", (_e, cx) => {
      this.filterFocused = false;
      cx.notify();
    });
    this.treeScroll = ScrollHandle.new();
    this.treeFocus = cx.focus_handle();
    this.dotfiles = savedDotfiles();
    if (checkingOnly) return;
    this.refresh(cx);
    this.findBetterChanges(cx);
    this.findNewAgents(this.on, cx);
    this.agentsOn = this.on ?? null;
    cx.timer.every(SYNC_MS, (cx) => this.follow(cx));
    cx.spawn(async (cx) => {
      const { settings, problems } = await loadSettings("better-files", DEFAULT_SETTINGS);
      for (const problem of problems) console.warn(`better-files mod.json settings: ${problem}`);
      this.findEditors(cx, Array.isArray(settings.editors) ? settings.editors : []);
      this.shareFileManager(settings.fileManager);
      cx.timer.every(Math.max(1000, duration(settings.refresh.tree, 10000)), (cx) => this.refresh(cx));
    });
    cx.spawn(async (cx) => {
      // "focus" gives the tree the keyboard, for a key bound to better-files.focus.
      for (;;) {
        const command = await nextCommand();
        if (command === "refresh") this.refresh(cx);
        else if (command === "focus") this.focusTree(cx);
      }
    });
  }

  // A closing tab takes its copies of images with it, and any copy still being made when it
  // closes goes as soon as it's done. Pictures from the web stay: every tab shares them, and
  // they're downloaded again after a day.
  async close() {
    this.closed = true;
    if (cleanupWorker?.owner === this) cleanupWorker = null;
    this.watchRequest?.cancel?.();
    this.watchRequest = null;
    if (this.imageReading || this.markdownLocalPending?.size) this.markCleanupPending(true);
    cacheOwners.delete(this.viewerId);
    if (cleanupProtectedOwners.delete(this.viewerId)) this.markCleanupPending(false);
    const copies = [...new Set([this.imageCopy, ...(this.imageCopies ?? []), ...(this.markdownCopies?.values() ?? [])])].filter((c) => c && !c.startsWith("mods/better-files/.cache/web-"));
    this.queueCleanup(copies);
    if (await this.dropCopies(copies)) {
      this.imageCopies?.clear();
      this.imageCopy = null;
      const queue = shared(CLEANUP_KEY);
      if (Array.isArray(queue)) setShared(CLEANUP_KEY, queue.filter(path => !copies.includes(path)));
    }
  }

  queueCleanup(copies) {
    const queue = shared(CLEANUP_KEY);
    const previous = Array.isArray(queue) ? queue.filter(path => typeof path === "string" && CACHE_COPY.test(path)) : [];
    const all = [...new Set([...previous, ...copies.filter(path => CACHE_COPY.test(path))])];
    if (all.length > CLEANUP_LIMIT) this.markCleanupPending(false);
    setShared(CLEANUP_KEY, all.slice(0, CLEANUP_LIMIT));
  }

  markCleanupPending(wait) {
    setShared(CLEANUP_GENERATION, (Number(shared(CLEANUP_GENERATION)) || 0) + 1);
    setShared(CLEANUP_OVERFLOW, true);
    if (wait) setShared("better-files.cleanupNotBefore", Math.max(Number(shared("better-files.cleanupNotBefore")) || 0, Date.now() + 15000));
  }

  releaseCacheOwner() {
    cacheOwners.delete(this.viewerId);
  }

  retryCleanup(cx) {
    if (this.closed) return;
    let queue = shared(CLEANUP_KEY);
    if (Array.isArray(queue) && queue.length > CLEANUP_LIMIT) {
      this.queueCleanup([]);
      queue = shared(CLEANUP_KEY);
    }
    const overflow = shared(CLEANUP_OVERFLOW) === true;
    if (cleanupWorker || Date.now() < (this.cleanupNext ?? 0) || (!Array.isArray(queue) && !overflow)) return;
    if (Date.now() < (Number(shared("better-files.cleanupNotBefore")) || 0)) return;
    const viewers = shared("better-files.viewers") ?? {};
    const active = [...Object.keys(viewers), ...cacheOwners];
    if (this.mode === "viewer" && this.viewerId) active.push(this.viewerId);
    const batch = (Array.isArray(queue) ? queue : []).filter(path => typeof path === "string" && CACHE_COPY.test(path) &&
      !active.some(id => path.startsWith(`mods/better-files/.cache/${id}-`))).slice(0, CLEANUP_BATCH);
    if (!batch.length && !overflow) return;
    this.cleanupNext = Date.now() + CLEANUP_DELAY_MS;
    const worker = { owner: this };
    cleanupWorker = worker;
    cx.spawn(async () => {
      try {
        if (batch.length) {
          const failed = [];
          for (const path of batch) {
            const owners = [...cacheOwners, ...Object.keys(shared("better-files.viewers") ?? {})];
            if (cleanupWorker !== worker) return;
            if (owners.some(id => path.startsWith(`mods/better-files/.cache/${id}-`)) || !(await this.dropCopies([path]))) failed.push(path);
            if (cleanupWorker !== worker) return;
          }
          const latest = shared(CLEANUP_KEY);
          if (Array.isArray(latest)) {
            setShared(CLEANUP_KEY, latest.filter(path => !batch.includes(path)));
            this.queueCleanup(failed);
          }
        }
        if (overflow && Date.now() >= (Number(shared("better-files.cleanupNotBefore")) || 0)) await this.sweepCleanup(active, worker);
      } finally {
        if (cleanupWorker === worker) cleanupWorker = null;
      }
    });
  }

  async sweepCleanup(active, worker) {
    const generation = Number(shared(CLEANUP_GENERATION)) || 0;
    if (this.cleanupGeneration !== generation) {
      this.cleanupGeneration = generation;
      this.cleanupOffset = 0;
      this.cleanupSawCopies = false;
      this.cleanupSawProtected = false;
      this.cleanupConfirmEmpty = false;
    }
    const offset = this.cleanupOffset ?? 0;
    const { program, args } = pickCleanupListing(`${appHome()}/mods/better-files/.cache`, offset, window()?.platform);
    const result = await exec(program, args, {}).catch(() => null);
    if (cleanupWorker !== worker || result?.code !== 0 || generation !== (Number(shared(CLEANUP_GENERATION)) || 0) ||
      Date.now() < (Number(shared("better-files.cleanupNotBefore")) || 0)) return;
    const viewers = shared("better-files.viewers") ?? {};
    active = [...new Set([...active, ...Object.keys(viewers), ...cacheOwners])];
    for (const id of cleanupProtectedOwners) if (!active.includes(id)) cleanupProtectedOwners.delete(id);
    const fields = result.stdout.split("\0");
    const count = (fields.length - 1) / 2;
    const consumed = Math.min(count, CLEANUP_BATCH);
    const names = [];
    for (let i = 0; i < consumed * 2; i += 2) {
      const name = fields[i + 1];
      if (fields[i] !== "f" || !SWEEP_COPY.test(name)) continue;
      const owners = active.filter(id => name.startsWith(`${id}-`));
      if (owners.length) {
        this.cleanupSawProtected = true;
        for (const id of owners) cleanupProtectedOwners.add(id);
      } else names.push(`mods/better-files/.cache/${name}`);
    }
    let removed = 0;
    if (names.length) {
      this.cleanupSawCopies = true;
      this.cleanupConfirmEmpty = false;
      for (const path of names) {
        if (cleanupWorker !== worker || generation !== (Number(shared(CLEANUP_GENERATION)) || 0)) return;
        const owners = [...cacheOwners, ...Object.keys(shared("better-files.viewers") ?? {})];
        const protectedBy = owners.filter(id => path.startsWith(`mods/better-files/.cache/${id}-`));
        if (protectedBy.length) {
          this.cleanupSawProtected = true;
          for (const id of protectedBy) cleanupProtectedOwners.add(id);
        } else {
          if (await this.dropCopies([path])) removed++;
          if (cleanupWorker !== worker || generation !== (Number(shared(CLEANUP_GENERATION)) || 0)) return;
        }
      }
    }
    if (count > consumed) this.cleanupOffset = offset + consumed - removed;
    else {
      this.cleanupOffset = 0;
      if (!this.cleanupSawCopies && !this.cleanupSawProtected && !(shared(CLEANUP_KEY)?.length)) {
        if (this.cleanupConfirmEmpty && generation === (Number(shared(CLEANUP_GENERATION)) || 0) &&
          Date.now() >= (Number(shared("better-files.cleanupNotBefore")) || 0)) setShared(CLEANUP_OVERFLOW, false);
        else this.cleanupConfirmEmpty = true;
      } else this.cleanupConfirmEmpty = false;
      this.cleanupSawCopies = false;
      this.cleanupSawProtected = false;
    }
  }

  // Keeps up with the focused pane, tabs closing, and questions left by the menu.
  follow(cx) {
    this.retryCleanup(cx);
    if (this.placeKey() !== this.key) {
      this.refresh(cx);
      if ((this.on ?? null) !== this.agentsOn) {
        this.agentsOn = this.on ?? null;
        this.findNewAgents(this.on, cx);
      }
    }
    this.pruneViewers();
    this.syncCompose(cx);
  }

  render() {
    if (this.mode === "menu") return this.menuView();
    if (this.mode === "viewer") return this.viewerView();
    return this.sidebarView();
  }
}

Object.assign(
  BetterFiles.prototype,
  readMethods,
  openMethods,
  outsideMethods,
  agentMethods,
  menuMethods,
  treeMethods,
  filterMethods,
  toolMethods,
  keyMethods,
  viewerMethods,
  contextMenuMethods,
);

export default BetterFiles;
