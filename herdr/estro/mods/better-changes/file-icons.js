// Picks a file's or folder's icon from Better Icons, the way VS Code's Material Icon Theme does.
// Shared between this repo's mods: each keeps an identical copy, because a mod can't import from
// another's folder. The icons themselves are read by path, so only Better Icons holds them.
import { appHome, readTextFile, watchFolder } from "herdr";

const PACK = "mods/better-icons";

// Read once per copy and shared by its views; reread only when Better Icons' folder changes.
let table = null;
const POLL_MS = 10000;
// The longest path rule in the table has this many parts; the tests check it.
const RULE_PARTS = 2;

// The table, or null when Better Icons isn't installed, so the caller keeps its own icons.
// reread: read icons.json again, as after an update or an uninstall. A reread gives a new object,
// so a view can tell by identity alone whether it needs to redraw.
export async function loadFileIcons(reread = false) {
  if (!table || reread) table = await readTable();
  return table;
}

// Keeps view.fileIcons current and redraws the view when it changes: now, whenever Better Icons'
// folder changes, as on an update, and every 10 seconds while there's no folder to watch, so
// installing it needs no restart.
export function followFileIcons(view, cx) {
  view.fileIcons ??= null;
  const show = async (cx, reread) => {
    const next = await loadFileIcons(reread);
    if (next === view.fileIcons) return;
    view.fileIcons = next;
    cx.notify();
  };
  cx.spawn(async (cx) => {
    await show(cx, false);
    for (;;) {
      try {
        await watchFolder(`${appHome()}/${PACK}`);
      } catch {
        await new Promise((done) => cx.timer.after(POLL_MS, done));
      }
      await show(cx, true);
    }
  });
}

async function readTable() {
  try {
    const text = await readTextFile(`${appHome()}/${PACK}/icons.json`);
    const read = text ? JSON.parse(text) : null;
    return read?.file && read?.folder && read?.fileNames && read?.folderNames && read?.fileExtensions ? read : null;
  } catch {
    return null;
  }
}

// Herdr's settings say nothing of light or dark, so a theme counts as light when its background is.
export function isLight(background) {
  const hex = /^#([0-9a-f]{3}|[0-9a-f]{6})([0-9a-f]{2})?$/i.exec(background ?? "")?.[1];
  if (!hex) return false;
  const [r, g, b] = hex.length === 3 ? [...hex].map((c) => parseInt(c + c, 16)) : [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16));
  return 0.299 * r + 0.587 * g + 0.114 * b > 128;
}

// path: the full path, so a rule such as .github/workflows matches whichever folder is on show.
// A rule for a path beats a name, a name beats an extension, and the longest extension wins.
export function fileIcon(table, path, { dir = false, open = false, light = false } = {}) {
  if (!table) return null;
  const parts = path.toLowerCase().split("/").filter(Boolean);
  const name = parts.at(-1) ?? "";
  const find = (kind, key) => (light && table.light?.[kind]?.[key]) || table[kind]?.[key];
  const names = dir ? "folderNames" : "fileNames";
  let icon;
  for (let i = Math.max(0, parts.length - RULE_PARTS); i < parts.length - 1 && !icon; i++)
    icon = find(names, parts.slice(i).join("/"));
  icon ??= find(names, name);
  for (let dot = name.indexOf("."); !dir && !icon && dot !== -1; dot = name.indexOf(".", dot + 1))
    icon = find("fileExtensions", name.slice(dot + 1));
  icon ??= dir ? table.folder : table.file;
  if (dir && open) icon = table.open?.[icon] ?? icon;
  return `${PACK}/icons/${icon}.svg`;
}
