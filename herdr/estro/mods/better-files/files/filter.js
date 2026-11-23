// The filter: every file under the folder, which names match, and the tree that shows them.
// Plain data, no Herdr calls.
import { baseName, sortEntries } from "./model.js";

export const MAX_MATCHES = 200;
export const MAX_INDEXED = 40000;

// A NUL-separated listing of files, relative to the folder on show, with the folders they're
// in added, since a list of files names a folder only through what's inside it. A listing that
// was cut short ends mid-name, so its last piece is dropped.
export function indexOf(stdout) {
  const text = String(stdout ?? "");
  const pieces = text.split("\0");
  const whole = text.endsWith("\0") || !text;
  if (!whole) pieces.pop();
  const files = new Set();
  let capped = !whole;
  for (const piece of pieces) {
    const path = piece.replace(/^\.\//, "");
    if (!path || path === ".") continue;
    if (files.size >= MAX_INDEXED) {
      capped = true;
      break;
    }
    files.add(path);
  }
  const dirs = new Set();
  for (const file of files)
    for (let cut = file.lastIndexOf("/"); cut > 0; cut = file.lastIndexOf("/", cut - 1)) {
      const dir = file.slice(0, cut);
      if (dirs.has(dir)) break;
      dirs.add(dir);
    }
  return { files: [...files], dirs: [...dirs], capped };
}

// A file or folder matches when its name holds the query, or, for a query with a /, its path.
// Names that start with the query come first, then shorter paths. With dotfiles off, nothing
// whose path has a part starting with a dot matches.
export const isHidden = (path) => path.split("/").some((part) => part.startsWith("."));

export function findMatches(index, query, { dotfiles = true } = {}) {
  const wanted = String(query ?? "").trim().toLowerCase();
  if (!wanted || !index) return { hits: [], more: false };
  const byPath = wanted.includes("/");
  const hits = [];
  const consider = (path, dir) => {
    if (!dotfiles && isHidden(path)) return;
    const at = (byPath ? path : baseName(path)).toLowerCase().indexOf(wanted);
    if (at !== -1) hits.push({ path, dir, early: at === 0 });
  };
  for (const dir of index.dirs) consider(dir, true);
  for (const file of index.files) consider(file, false);
  hits.sort(
    (a, b) => Number(b.early) - Number(a.early) || a.path.length - b.path.length || (a.path < b.path ? -1 : 1),
  );
  return { hits: hits.slice(0, MAX_MATCHES).map(({ path, dir }) => ({ path, dir })), more: hits.length > MAX_MATCHES };
}

// The matches as tree rows, each under the folders that hold it, in the tree's own order.
// A folder shows open when matches are inside it; a matching folder is marked as a hit.
export function matchRows(hits) {
  const top = new Map();
  for (const { path, dir } of hits) {
    const parts = path.split("/");
    let level = top;
    parts.forEach((name, i) => {
      const last = i === parts.length - 1;
      let node = level.get(name);
      if (!node) level.set(name, (node = { name, dir: last ? dir : true, hit: false, inside: new Map() }));
      if (last) node.hit = true;
      level = node.inside;
    });
  }
  const rows = [];
  const walk = (level, prefix, depth) => {
    for (const { name } of sortEntries([...level.values()])) {
      const node = level.get(name);
      const relative = prefix ? `${prefix}/${name}` : name;
      rows.push({ relative, name, dir: node.dir, depth, hit: node.hit, open: node.inside.size > 0 });
      walk(node.inside, relative, depth + 1);
    }
  };
  walk(top, "", 0);
  return rows;
}

// The folders to open so a path shows in the tree: each one above it, and itself if a folder.
export function foldersTo(path, dir) {
  const parts = path.split("/");
  const count = dir ? parts.length : parts.length - 1;
  return Array.from({ length: count }, (_, i) => parts.slice(0, i + 1).join("/"));
}
