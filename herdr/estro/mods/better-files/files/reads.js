// Tree behavior follows Herdr 0.1.16's Files mod, with Better Files'
// centre-tab location, filter, per-folder settings, and refillable row limit.
import { spaces, panes, focused, exec, watchFolder, window } from "herdr";
import { PER_FOLDER, TOTAL_ROWS, parseStatus, sortEntries } from "./model.js";
import { pickIndex, pickListing } from "./shell.js";
import { indexOf } from "./filter.js";

const INDEX_BYTES = 4000000;
const INDEX_DEPTH = 12;
// A home folder or /, which hold far more than a project, are searched less deep.
const SHALLOW_DEPTH = 5;
const SHALLOW_ROOT = /^\/(?:(?:home|Users)\/[^/]+|root)?$/;
const REINDEX_MS = 30000;
// A folder that keeps changing, such as one an agent is writing in, is read again at most this often.
const RESTALE_MS = 5000;
const SKIPPED = [".git", "node_modules", ".venv", "__pycache__", "target", "dist", ".next"];

// Every file under the folder, for the filter: Git's own list where there is one, so ignored
// files stay out, else find without the folders that are usually huge, cut at a size. A folder
// Git ignores, such as node_modules, gets an empty list from Git, so find reads it instead.
async function everyFile(root, on) {
  const lsFiles = (...flags) =>
    exec("git", ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.quotepath=off", "ls-files", "-z", ...flags], { cwd: root, on }).catch(
      () => null,
    );
  // Git still lists a tracked file that was deleted but not staged, so those come out.
  const [git, gone] = await Promise.all([lsFiles("--cached", "--others", "--exclude-standard"), lsFiles("--deleted")]);
  if (git?.code === 0 && git.stdout) {
    if (gone?.code !== 0 || !gone.stdout) return git.stdout;
    const deleted = new Set(gone.stdout.split("\0"));
    return git.stdout
      .split("\0")
      .filter((path) => !deleted.has(path))
      .join("\0");
  }
  const depth = SHALLOW_ROOT.test(root.replace(/\/+$/, "") || "/") ? SHALLOW_DEPTH : INDEX_DEPTH;
  const prune = SKIPPED.map((name) => `-name '${name}'`).join(" -o ");
  const script = `find . -mindepth 1 -maxdepth "$1" \\( ${prune} \\) -prune -o ! -type d -print0 | head -c "$2"`;
  const windowsIndex = async () => {
    const { program, args } = pickIndex(root, depth, INDEX_BYTES);
    return exec(program, args, { cwd: root, on });
  };
  let found;
  if (!on && window()?.platform === "windows") found = await windowsIndex();
  else {
    try {
      found = await exec("sh", ["-c", script, "index", String(depth), String(INDEX_BYTES)], { cwd: root, on });
    } catch (e) {
      if (!on || !String(e).includes("cannot start sh: program not found")) throw e;
      found = await windowsIndex();
    }
  }
  if (found.code !== 0) throw new Error(found.stderr || "Cannot list this folder.");
  return found.stdout;
}

// Each read of a folder is bounded, and the names come back null-separated, so no file name
// can break the list. Adapted from Herdr's shipped Files mod; platform branching (sh vs
// PowerShell 5.1) lives in shell.js. Like Herdr's Files, a remote machine without sh
// retries with PowerShell.
async function directory(path, on) {
  const platform = on ? null : window()?.platform;
  const listing = pickListing(path, PER_FOLDER, platform);
  let r;
  try {
    r = await exec(listing.program, listing.args, { on });
  } catch (e) {
    if (!on || !String(e).includes("cannot start sh: program not found")) throw e;
    const windows = pickListing(path, PER_FOLDER, "windows");
    r = await exec(windows.program, windows.args, { on });
  }
  if (r.code !== 0) throw new Error(r.stderr || "Cannot list this folder.");
  const fields = r.stdout.split("\0");
  const out = [];
  for (let i = 0; i + 1 < fields.length; i += 2)
    out.push({ name: fields[i + 1], dir: fields[i] === "d" });
  return out;
}

// Where a space is now: a terminal's folder in its shown tab, else in its other tabs. The
// space's own folder is where it was made, which its terminals may have long left.
function liveFolder(space) {
  const tabs = space?.tabs ?? [];
  const order = [...tabs.filter((t) => t.active), ...tabs.filter((t) => !t.active)].map((t) => t.id);
  const all = panes();
  for (const tab of order) {
    const pane = all.find((p) => p.tab === tab && p.cwd);
    if (pane) return pane.cwd;
  }
  return null;
}

export const readMethods = {
  // The focused pane's folder. A file or diff tab has no folder of its own, so looking at
  // one keeps the tree where it was instead of jumping back to the space's.
  location() {
    const space = spaces().find((s) => s.active);
    const f = focused();
    const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
    const on =
      f?.pane === null
        ? f.terminal?.includes("/")
          ? f.terminal.split("/")[0]
          : null
        : (space?.machine ?? null);
    // A file or diff tab carries no cwd of its own: only a terminal pane (a pane entry
    // with no mod) contributes one, or the focused entry's cwd when it names a terminal.
    // `f?.terminal` is null for mod panes even while their `mod` is still attaching,
    // so it keeps a just-opened viewer from leaking the pane's default cwd.
    const cwd =
      pane && !pane.mod && f?.terminal
        ? (pane.cwd || f?.cwd || null)
        : !pane && f?.terminal
          ? (f?.cwd ?? null)
          : null;
    if (!cwd && this.place?.space === space?.id && this.place?.cwd) return this.place;
    return (this.place = { cwd: cwd || liveFolder(space) || space?.folder, on, space: space?.id });
  },

  placeKey() {
    return JSON.stringify(this.location());
  },

  current(context) {
    return this.context === context && this.placeKey() === context.key;
  },

  // A folder's own state is kept, so coming back to it is where you left it.
  refresh(cx) {
    const { cwd, on } = this.location();
    const key = this.placeKey();
    if (key !== this.key) {
      this.watchRequest?.cancel?.();
      this.watchRequest = null;
      if (this.key) this.saved.set(this.key, { folders: this.folders });
      const kept = this.saved.get(key);
      this.key = key;
      this.context = { key };
      this.root = cwd;
      this.on = on;
      this.entries = new Map();
      this.folderLists = new Map();
      this.folderReads = new Map();
      this.folders = kept?.folders ?? new Set();
      this.marks = {};
      this.top = null;
      this.treeError = null;
      this.indexError = null;
      this.index = null;
      this.limited = false;
      this.scrollTo = null;
      this.cursor = null;
      this.watch(cx);
    }
    this.ensureIndex(cx);
    if (!cwd || this.loading === this.context) return;
    const token = this.context;
    this.loading = token;
    this.limited = false;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        let folderError = null;
        for (const path of ["", ...this.folders]) {
          if (!this.current(token)) return;
          if (path && !this.folders.has(path)) continue;
          try {
            await this.loadFolder(path, cwd, on, token);
          } catch (e) {
            if (!path) throw e;
            if (this.current(token)) {
              const cut = path.lastIndexOf("/");
              const parent = cut < 0 ? "" : path.slice(0, cut);
              const name = path.slice(cut + 1);
              const listing = this.folderLists.get(parent);
              const missing = listing && listing.length <= PER_FOLDER && !listing.some(entry => entry.dir && entry.name === name);
              if (missing) {
                for (const folder of [...this.folders]) if (folder === path || folder.startsWith(`${path}/`)) {
                  this.folders.delete(folder);
                  this.folderLists.delete(folder);
                  this.folderReads.delete(folder);
                }
                this.allocateEntries();
              } else {
                folderError ??= e.message ?? String(e);
              }
            }
          }
        }
        await this.loadMarks(cwd, on, token);
        if (this.current(token)) this.treeError = folderError;
      } catch (e) {
        if (this.current(token)) this.treeError = e.message ?? String(e);
      } finally {
        if (this.loading === token) this.loading = null;
        cx.notify();
      }
    });
  },

  async loadFolder(path, root, on, token) {
    if (!this.current(token)) return;
    const request = {};
    const reads = this.folderReads;
    reads.set(path, request);
    let list;
    try {
      list = await directory(path ? `${root}/${path}` : root, on);
    } catch (e) {
      if (!this.current(token) || reads.get(path) !== request) return;
      throw e;
    }
    if (!this.current(token) || reads.get(path) !== request || (path && !this.folders.has(path))) return;
    this.folderLists.set(path, list);
    this.allocateEntries();
  },

  allocateEntries() {
    const entries = new Map();
    let used = 0;
    let limited = false;
    const walk = (path) => {
      const list = this.folderLists.get(path);
      if (!list) return;
      const count = Math.min(PER_FOLDER, Math.max(0, TOTAL_ROWS - used));
      if (list.length > count) limited = true;
      const selected = sortEntries(list.slice(0, count));
      entries.set(path, selected);
      used += selected.length;
      for (const entry of selected) {
        const child = path ? `${path}/${entry.name}` : entry.name;
        if (entry.dir && this.folders.has(child)) walk(child);
      }
    };
    walk("");
    this.entries = entries;
    this.limited = limited;
  },

  // Writes nothing under .git, or the folder watch would see its own read and refresh again.
  async loadMarks(root, on, token) {
    const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd: root, on }).catch(
      () => null,
    );
    if (!this.current(token)) return;
    if (top?.code !== 0) {
      this.top = null;
      this.marks = {};
      return;
    }
    const status = await exec(
      "git",
      [
        "--no-optional-locks",
        "-c",
        "core.fsmonitor=false",
        "status",
        "--porcelain=v1",
        "-z",
        "--no-renames",
        "--untracked-files=all",
      ],
      { cwd: root, on },
    ).catch(() => null);
    if (!this.current(token)) return;
    // Git's spelling of the top (forward slashes, its own drive-letter case on Windows) is
    // kept; marks are compared through markKey, so it needn't match the root's.
    this.top = top.stdout.trim();
    if (status?.code === 0) this.marks = parseStatus(status.stdout, this.top);
  },

  // A local folder says when it changes; another machine's is read on the timer alone.
  watch(cx) {
    const { root, on, key, context } = this;
    if (on || !root || this.watched === context) return;
    this.watched = context;
    cx.spawn(async (cx) => {
      try {
        while (!this.closed && this.context === context) {
          const request = watchFolder(root);
          this.watchRequest = request;
          await request;
          if (this.watchRequest === request) this.watchRequest = null;
          if (this.closed || !this.current(context)) return;
          this.changes = (this.changes ?? 0) + 1;
          if (this.index?.key === key) this.index.stale = true;
          this.refresh(cx);
        }
      } catch {
        // No watcher here: the timer still refreshes.
      }
      if (this.watched === context) this.watched = null;
    });
  },

  // The filter's list of every file, read when it's first needed, again once the folder
  // changes on disk but at most every 5 seconds, and every 30 for a folder that can't be watched.
  ensureIndex(cx) {
    const { root, on, key, context } = this;
    if (!root || !this.filterText() || this.indexing === context) return;
    const index = this.index?.key === key ? this.index : null;
    const age = index ? Date.now() - index.at : Infinity;
    if (index && age < (index.stale ? RESTALE_MS : REINDEX_MS)) {
      // The last change before a quiet spell still gets read, once the wait is over.
      if (index.stale && !this.reindexLater) {
        this.reindexLater = true;
        cx.timer.after(RESTALE_MS - age, (cx) => {
          this.reindexLater = false;
          this.ensureIndex(cx);
        });
      }
      return;
    }
    this.indexing = context;
    cx.spawn(async (cx) => {
      try {
        // A change on disk while the list is read leaves it stale, to be read again.
        const changes = this.changes;
        const listing = await everyFile(root, on);
        if (this.current(context)) {
          this.index = { key, at: Date.now(), stale: this.changes !== changes, ...indexOf(listing) };
          this.indexError = null;
        }
      } catch (e) {
        if (this.current(context)) this.indexError = e.message ?? String(e);
      } finally {
        if (this.indexing === context) this.indexing = null;
        cx.notify();
      }
    });
  },

  toggleFolder(path, cx) {
    if (this.folders.has(path)) {
      for (const folder of [...this.folders]) if (folder === path || folder.startsWith(`${path}/`)) {
        this.folders.delete(folder);
        this.entries.delete(folder);
        this.folderLists.delete(folder);
      }
      this.allocateEntries();
    } else {
      this.folders.add(path);
      const { root, on, context } = this;
      cx.spawn(async (cx) => {
        try {
          await this.loadFolder(path, root, on, context);
        } catch (e) {
          if (this.current(context)) this.treeError = e.message ?? String(e);
        }
        cx.notify();
      });
    }
    cx.notify();
  },

};
