// Auto names: a tab follows what runs in it. An agent takes its terminal's title as Herdr gives
// it, a shell its folder, another program its name. The names this mod set are kept in
// `shared("better-tabs.names")`, so a name that differs from them is the person's own and is
// left alone; renaming a tab to nothing hands it back. Logic only: the bar's copy runs
// `tab.rename` from its timer, never in render.
import { spaces, panes, run, shared, setShared, home, checking } from "herdr";

export const NAMES_KEY = "better-tabs.names";

// Herdr applies a rename a moment later. A request is waited for this long, then asked again
// if the tab still shows the name before it.
const RETRY_MS = 2000;
// A closed tab's record is kept this long, so a moment where Herdr lists fewer tabs (startup,
// restore) doesn't forget which names the person typed.
const FORGET_MS = 10000;
// Longer names are cut, so the name asked for is the name Herdr keeps.
const MAX_LENGTH = 80;

// One line, single spaces, no longer than MAX_LENGTH; null when nothing is left.
export function cleanName(text) {
  if (typeof text !== "string") return null;
  const name = text.replace(/\s+/g, " ").trim();
  if (!name) return null;
  return name.length > MAX_LENGTH ? `${name.slice(0, MAX_LENGTH - 1).trimEnd()}…` : name;
}

// An agent's title without the status glyph some agents put in front of it while they work
// (✳, ✻, ·, a braille spinner), so the tab isn't renamed on every frame.
function titleText(title, pane) {
  const text = String(title ?? "")
    .replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}~/]+/u, "")
    .replace(/^\[ [!.] \] /, "")
    .trim();
  if (!text || text === pane?.terminal || text.includes("@") || text.toLowerCase() === pane?.program?.key)
    return null;
  // A path is location, not a useful tab topic.
  if (/^[~/]|^[A-Za-z]:\\/.test(text)) return null;
  return cleanName(text);
}

function homeFolder() {
  try {
    return cleanPath(home());
  } catch {
    return null;
  }
}

const cleanPath = (path) => (typeof path === "string" ? path.replace(/\/+$/, "") : null);

// A folder's last part, ~ at home and / at the root; null with no folder.
export function folderName(cwd, homePath = homeFolder()) {
  if (!cwd) return null;
  const path = cleanPath(cwd);
  if (!path) return "/";
  if (homePath && path === homePath) return "~";
  return path.slice(path.lastIndexOf("/") + 1);
}

// A title that only says where the agent is: the folder, its path, or a short mark and the
// folder ("π - lantern").
function onlyFolder(title, cwd, folder) {
  if (!folder) return false;
  if (title === folder || title === cleanPath(cwd)) return true;
  const marked = /^(.{1,3}) [-–—|:] (.+)$/u.exec(title);
  return Boolean(marked && marked[2] === folder);
}

// What a pane would call its tab, and how strongly. An agent's title is its topic, unless it's
// empty or only its folder, and then the agent goes by its name. A mod's pane has no program,
// so it names nothing.
function paneName(pane, homePath) {
  const program = pane.program;
  if (!program) return null;
  const folder = folderName(pane.cwd, homePath);
  if (program.shell) return { name: folder, rank: 1 };
  const name = cleanName(program.name);
  if (!program.agent) return { name, rank: 2 };
  const title = titleText(pane.title, pane);
  const topic = title && !onlyFolder(title, pane.cwd, folder);
  return { name: topic ? title : name, rank: 3 };
}

// The name a tab's panes give it, and every name it could have had from them, so a tab named
// before this mod knew it can be told from one the person named.
function tabWants(tabPanes, homePath) {
  let best = null;
  const known = new Set();
  for (const pane of tabPanes) {
    const named = paneName(pane, homePath);
    if (!named) continue;
    const names = [named.name, titleText(pane.title, pane), cleanName(pane.program.name)];
    for (const name of [...names, folderName(pane.cwd, homePath)]) if (name) known.add(name);
    if (named.name && named.rank > (best?.rank ?? 0)) best = named;
  }
  return { name: best?.name ?? null, known };
}

// What to ask Herdr for now. records: tab ID → { auto: the name this mod set } or
// { manual: true }, with { pending, at } while a rename is on its way and { gone } once the tab
// has closed. They're shared, so every copy of the bar waits for the same request. Returns the
// renames and the records to keep, without changing what it was given.
export function planNames(allSpaces, allPanes, records, now, homePath = homeFolder()) {
  const tabs = allSpaces.flatMap((space) => space.tabs ?? []);
  // Herdr lists no tabs only while it starts or restores, so nothing is decided then.
  if (!tabs.length) return { renames: [], records };
  const byTab = new Map();
  for (const pane of allPanes) {
    if (!byTab.has(pane.tab)) byTab.set(pane.tab, []);
    byTab.get(pane.tab).push(pane);
  }
  const renames = [];
  const next = {};
  for (const tab of tabs) {
    const wants = tabWants(byTab.get(tab.id) ?? [], homePath);
    const current = tab.named ? cleanName(tab.name) : null;
    let record = records[tab.id];
    if (record?.gone !== undefined) record = withoutKeys(record, ["gone"]);
    if (record?.pending !== undefined) {
      const before = record.auto ?? null;
      if (current === record.pending) record = { auto: record.pending };
      else if (now - record.at < RETRY_MS) {
        next[tab.id] = record;
        continue;
      }
      // The rename didn't land: ask again if the tab still shows the name before it, else the
      // person renamed it meanwhile.
      else if (current === before) record = before === null ? undefined : { auto: before };
      else record = current === null ? undefined : { manual: true };
    }
    if (!tab.named) record = undefined;
    else if (!record) {
      if (wants.known.size) record = wants.known.has(current) ? { auto: current } : { manual: true };
    } else if (record.auto !== undefined && current !== record.auto) record = { manual: true };
    if (record?.manual) {
      next[tab.id] = record;
      continue;
    }
    if (wants.name && wants.name !== current) {
      renames.push({ id: tab.id, name: wants.name });
      record = { ...(record?.auto !== undefined ? { auto: record.auto } : {}), pending: wants.name, at: now };
    }
    if (record) next[tab.id] = record;
  }
  const open = new Set(tabs.map((tab) => tab.id));
  for (const [id, record] of Object.entries(records)) {
    if (open.has(id)) continue;
    const gone = record.gone ?? now;
    if (now - gone < FORGET_MS) next[id] = { ...record, gone };
  }
  return { renames, records: next };
}

function withoutKeys(record, keys) {
  const copy = { ...record };
  for (const key of keys) delete copy[key];
  return copy;
}

export const nameMethods = {
  nameTabs(now = Date.now()) {
    // Until the installed settings are read, auto_name may be off.
    if (checking() || !this.settingsReady || !this.settings.tabs.auto_name) return;
    const saved = shared(NAMES_KEY) ?? {};
    const { renames, records } = planNames(spaces(), panes(), saved, now);
    for (const { id, name } of renames) {
      try {
        run("tab.rename", { id, name });
      } catch (error) {
        console.warn(`better-tabs: couldn't name a tab: ${error.message ?? error}`);
      }
    }
    if (records !== saved && JSON.stringify(records) !== JSON.stringify(saved)) setShared(NAMES_KEY, records);
  },
};
