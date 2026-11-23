// model.js: what Better Search lists for what's typed. No Herdr calls here, so the tests run
// it as it is. main.js passes in the live data (spaces, agents, commands, files) and draws
// the rows this returns.

// A leading character narrows the search to one kind.
export const PREFIXES = { "@": "agents", ">": "commands", "/": "files", "~": "spaces", "?": "output", "#": "prs", "$": "issues" };
export const KINDS = { agents: "Agents", commands: "Commands", files: "Files", spaces: "Spaces", tabs: "Tabs", output: "Output", prs: "PRs", issues: "Issues" };
const PREFIX_OF = Object.fromEntries(Object.entries(PREFIXES).map(([p, kind]) => [kind, p]));
// Typed text with no prefix shows every tab that matches, then this many of each other kind.
const EACH = 5;
// A file search shows at most this many rows.
const FILES_SHOWN = 60;
const URGENT = { blocked: 0, done: 1, working: 2, idle: 3 };
const urgency = (status) => URGENT[status] ?? 4;

// How long ago, short: "now", "4m", "2h", "3d".
export function ago(ms, now) {
  if (!ms) return "";
  const m = Math.floor((now - ms) / 60000);
  return m < 1 ? "now" : m < 60 ? `${m}m` : m < 1440 ? `${Math.floor(m / 60)}h` : `${Math.floor(m / 1440)}d`;
}

// What a blocked agent is asking: the lowest line on its screen that ends in "?", without the
// boxes and bullets drawn around it. null: none.
// shortcut: agents report no question, so this reads the screen; a question without "?" is missed.
export function askOf(screen) {
  const lines = (screen ?? "").replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").split("\n");
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i].replace(/^[\s│┃|╭╰>❯●○◆*\-]+|[\s│┃|╮╯]+$/g, "");
    if (line.length > 3 && line.endsWith("?")) return line.slice(0, 160);
  }
  return null;
}

// Tabs you were in, newest first: `visit` puts one on top; `previous` is the one before `here`
// that still exists.
export function visit(list, id) {
  return id ? [id, ...(list ?? []).filter((x) => x !== id)].slice(0, 30) : list ?? [];
}
export function previous(list, here, exists) {
  return (list ?? []).find((id) => id !== here && exists(id)) ?? null;
}

export function parse(text) {
  const kind = PREFIXES[text[0]];
  return kind ? { kind, q: text.slice(1).trim() } : { kind: null, q: text.trim() };
}

// Fuzzy score of `q` in `text`, with the matched positions; null: no match. Your letters in
// order; word starts and runs rank higher. Herdr's palette ranks the same way.
export function fuzzy(q, text) {
  const t = text.toLowerCase();
  let score = 0;
  let at = 0;
  let run = 0;
  const hits = [];
  for (const ch of q.toLowerCase().replace(/\s+/g, "")) {
    const i = t.indexOf(ch, at);
    if (i < 0) return null;
    const start = i === 0 || /[\s:.\-_/]/.test(t[i - 1]);
    run = i === at && hits.length ? run + 1 : 0;
    score += 1 + (start ? 6 : 0) + run * 3 - Math.min(i - at, 6) * 0.3;
    hits.push(i);
    at = i + 1;
  }
  return { score: score - text.length * 0.02, hits };
}

// Ranks items by `q` against their title (highlighted) or, a little lower, their other words.
function rank(items, q) {
  if (!q) return items;
  return items
    .map((r) => {
      const title = fuzzy(q, r.title);
      const more = fuzzy(q, `${r.title} ${r.words ?? ""}`);
      const best = title ?? (more && { score: more.score - 4, hits: [] });
      return best && { ...r, score: best.score, hits: best.hits };
    })
    .filter(Boolean)
    .sort((a, b) => b.score - a.score);
}

const machineOf = (space) => space.machine ?? null;
const programs = (mine) => mine.map((a) => a.program?.name ?? "agent").join(" · ");

const where = (space) => [space.name, machineOf(space)].filter(Boolean).join(" · ");

// Every open tab in one list: the ones that need you first, then in space and tab order. Each
// says what runs in it (or, when its agent waits, what it asks) and, on the right, its space.
export function tabRows({ spaces, agents, teamOf = () => 0, asks = {}, last = null }, q) {
  const tabs = spaces.flatMap((space) =>
    space.tabs.map((tab) => {
      const mine = agents.filter((a) => a.tab === tab.id);
      const asking = mine.find((a) => a.status === "blocked" && asks[a.address]);
      const team = teamOf(mine);
      return {
        kind: "tab",
        id: tab.id,
        title: tab.name,
        words: [space.name, machineOf(space), programs(mine)].filter(Boolean).join(" "),
        sub: asking ? asks[asking.address] : programs(mine) + (team ? `  +${team}` : ""),
        ask: Boolean(asking),
        detail: where(space),
        status: tab.status,
        since: tab.changed_at,
        here: space.active && tab.active,
        last: tab.id === last,
        agent: (asking ?? mine[0])?.address ?? null,
        order: [urgency(tab.status), space.index, tab.index],
      };
    }),
  );
  tabs.sort((a, b) => a.order[0] - b.order[0] || a.order[1] - b.order[1] || a.order[2] - b.order[2]);
  return q ? rank(tabs, q) : tabs;
}

// Agents, the ones waiting for you first, each with its state spelled out.
export function agentRows({ agents, spaces = [], asks = {} }, q) {
  const tabs = new Map(spaces.flatMap((s) => s.tabs.map((t) => [t.id, t])));
  const items = [...agents]
    .sort((a, b) => urgency(a.status) - urgency(b.status) || b.pinned - a.pinned || b.seq - a.seq)
    .map((a) => {
      const ask = a.status === "blocked" ? asks[a.address] : null;
      return {
        kind: "agent",
        id: a.address,
        title: a.tab_name || a.title || a.address,
        words: `${a.space_name} ${a.program?.name ?? ""} ${a.app ?? ""} ${a.title ?? ""}`,
        sub: ask || (a.program?.name ?? "agent"),
        ask: Boolean(ask),
        detail: a.space_name,
        status: a.status,
        spell: true,
        since: tabs.get(a.tab)?.changed_at ?? null,
        here: a.focused,
        agent: a.address,
      };
    });
  return rank(items, q);
}

export function spaceRows({ spaces, machines = [] }, q) {
  const order = [...spaces].sort((a, b) => urgency(a.status) - urgency(b.status) || a.index - b.index);
  const items = order.map((s) => ({
    kind: "space",
    id: s.id,
    title: s.name,
    words: [machineOf(s), s.branch, s.folder].filter(Boolean).join(" "),
    detail: [s.branch, machineOf(s)].filter(Boolean).join(" · "),
    status: s.status,
    here: s.active,
  }));
  const fresh = [null, ...machines].map((m) => ({
    kind: "new-space",
    id: `new-space:${m ?? ""}`,
    title: m ? `New space on ${m}` : "New space",
    words: "new space machine",
    machine: m,
  }));
  return [...rank(items, q), ...(q ? rank(fresh, q) : fresh)];
}

// Herdr's commands people can run from a list: those that need only a name (Herdr asks for
// it) or nothing. Layouts and themes get one row each; settings sections too.
const POINTED = new Set([
  "space.move", "tab.move", "space.select", "tab.select", "pane.focus", "terminal.keep",
  "terminal.park", "terminal.kill", "terminal.show", "terminal.peek", "terminal.pin",
  "terminal.right_click", "terminal.scroll", "agent.focus", "layout.set", "layout.toggle",
  "layout.show", "layout.hide", "layout.resize", "layout.select", "overlay.close",
  "tab.settle", "tab.unsettle", "app.theme", "app.settings", "mod.open", "app.feedback",
]);
const SETTINGS = ["look", "machines", "alerts", "updates", "privacy"];

function titleOf(name) {
  const [noun, verb] = name.split(".");
  return `${verb.replace(/_/g, " ")} ${noun}`.replace(/^./, (c) => c.toUpperCase());
}

// "name" or "name:value", as keys.json binds them.
function bindingOf(name, args) {
  const v = Object.values(args)[0];
  return v === undefined ? name : `${name}:${v}`;
}

export function commandEntries({ commands, layouts = [], themes = [], keys = [], mac = false, modSettings = false }) {
  const known = new Set(commands.map((c) => c.name));
  const list = [];
  const add = (name, args, title, words = "") => known.has(name) && list.push({ name, args, title, words });
  for (const c of commands) {
    if (POINTED.has(c.name) || (mac && c.name.startsWith("window."))) continue;
    if (c.args.some((a) => a.required && a.name !== "name")) continue;
    add(c.name, {}, titleOf(c.name), `${c.name} ${c.about}`);
  }
  for (const l of layouts) add("layout.switch", { name: l }, `Layout: ${l}`, "look switch");
  for (const t of themes) add("app.theme", { name: t }, `Theme: ${t}`, "colors look");
  add("app.settings", {}, "Settings", "preferences options config");
  for (const s of SETTINGS) add("app.settings", { section: s }, `Settings: ${s}`, "preferences options config");
  if (modSettings) add("mod.open", { name: "better-config" }, "Mod settings", "better config preferences options");
  return list.map((e) => {
    const bound = keys.find((k) => k.section === "global" && k.action === bindingOf(e.name, e.args));
    return { kind: "command", id: `${e.name}:${JSON.stringify(e.args)}`, ...e, key: bound?.keys ?? null };
  });
}

export function commandRows(entries, recent, q) {
  const order = (r) => (recent.indexOf(r.id) + 1 || 999);
  if (q) return rank(entries, q).sort((a, b) => b.score - a.score || order(a) - order(b));
  return [...entries].sort((a, b) => order(a) - order(b));
}

// Files from `git ls-files`, relative to the space's folder.
export function fileRows(files, q, most = FILES_SHOWN) {
  const items = files.map((path) => {
    const slash = path.lastIndexOf("/");
    return { kind: "file", id: path, title: path.slice(slash + 1), words: path, detail: slash > 0 ? path.slice(0, slash) : "", path };
  });
  return rank(items, q).slice(0, most);
}

// Lines agents printed that hold `q` (not fuzzy: terminal text is too noisy for it), newest
// first. `output`: { address: text } read with `hc read`.
export function outputRows({ agents = [], output = {} }, q) {
  if (q.length < 2) return [];
  const needle = q.toLowerCase();
  const out = [];
  for (const a of agents) {
    const seen = new Set(); // Redrawn screens leave the same line in history many times.
    const lines = (output[a.address] ?? "").replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").split("\n");
    for (let i = lines.length - 1; i >= 0 && out.length < FILES_SHOWN * 4; i--) {
      const line = lines[i].replace(/^[\s│┃|⎿└├>❯●○◆*]+/, "").trimEnd();
      const at = line.toLowerCase().indexOf(needle);
      if (at < 0 || seen.has(line)) continue;
      seen.add(line);
      // Long lines are cut around the match, so it shows.
      const from = Math.max(0, at - 40);
      const title = (from ? "…" : "") + line.slice(from, from + 140);
      const shift = from ? from - 1 : 0;
      out.push({
        kind: "output",
        id: `${a.address}:${i}`,
        title,
        hits: [...needle].map((_, k) => at - shift + k),
        detail: `${a.tab_name || a.address} · ${a.space_name}`,
        agent: a.address,
        status: a.status,
        n: i - lines.length,
      });
    }
  }
  return out.sort((a, b) => b.n - a.n).slice(0, FILES_SHOWN);
}

// A section of the mixed search: its heading says how many there are when not all show, and
// `section` names the prefix that shows them all.
function section(kind, rows, total = rows.length, note = null) {
  if (!rows.length && !note) return [];
  return [{ kind: "head", title: KINDS[kind], section: kind, more: total > rows.length ? `${rows.length} of ${total}` : note }, ...rows];
}

// The text that shows every row of the selected row's section, or null (Tabs show them all).
export function drill(rows, at, text) {
  for (let i = at; i >= 0; i--) {
    if (rows[i]?.kind !== "head") continue;
    const p = PREFIX_OF[rows[i].section];
    return p ? p + parse(text).q : null;
  }
  return null;
}

// The rows for what's typed. `data`: { spaces, agents, machines, commands (entries), recent,
// files (null while loading) }.
export function search(data, text) {
  const { kind, q } = parse(text);
  const newTab = { kind: "new-tab", id: "new-tab", title: "New tab", words: "new tab" };
  if (kind === "agents") return agentRows(data, q);
  if (kind === "spaces") return spaceRows(data, q);
  if (kind === "commands") return commandRows(data.commands, data.recent ?? [], q);
  if (kind === "files") return fileRows(data.files ?? [], q);
  if (kind === "output") return outputRows(data, q);
  if (kind === "prs") return prRows(data.prs);
  if (kind === "issues") return issueRows(data.issues);
  if (!q) return [...tabRows(data, ""), newTab, ...spaceRows({ spaces: [], machines: data.machines }, "")];
  const some = (kind, all) => section(kind, all.slice(0, EACH), all.length);
  return [
    ...section("tabs", tabRows(data, q)),
    ...some("agents", agentRows(data, q)),
    ...some("spaces", spaceRows(data, q).filter((r) => r.kind === "space")),
    ...some("commands", commandRows(data.commands, data.recent ?? [], q)),
    ...(data.files ? some("files", fileRows(data.files, q, Infinity)) : section("files", [], 0, "reading…")),
  ];
}

// owner/name of a GitHub remote URL (https, ssh or git@), or null.
export function githubRepo(remote) {
  const m = /^(?:(?:https?|ssh|git):\/\/(?:[^@/]+@)?([^/:]+)(?::\d+)?\/|git@([^:/]+):)([\w.-]+)\/([\w.-]+?)(?:\.git)?\/?$/.exec((remote ?? "").trim());
  if (!m) return null;
  const host = (m[1] ?? m[2]).toLowerCase();
  // SSH aliases such as github-work name the real host only in ~/.ssh/config.
  return host === "github.com" || /^github(\.com)?-|^ssh\.github\.com$/.test(host) ? `${m[3]}/${m[4]}` : null;
}

// A link without its scheme, for showing: github.com/o/r/pull/12.
const shortLink = (url) => (url ?? "").replace(/^https?:\/\//, "");

// PRs for #, from what Branch PR's helper found ([] until it answers).
export function prRows(prs) {
  return (Array.isArray(prs) ? prs : []).map((p) => ({
    kind: "pr",
    id: `pr:${p.repository ?? ""}#${p.number}`,
    title: `#${p.number} ${p.title}`,
    sub: [p.author?.login, p.headRefName].filter(Boolean).join(" · "),
    state: p.isDraft ? "draft" : (p.state ?? "").toLowerCase(),
    detail: shortLink(p.url),
    number: p.number,
    repo: p.repository ?? null,
    url: p.url,
  }));
}

// Issues for $, from what Branch Issue's helper found: Linear's (identifier, state.name) and,
// from Branch Issue 3, GitHub's (number, state), told apart by `source`. `ref` is how Branch
// Issue 3 names one: "linear:ENG-3", "github:16".
export function issueRows(issues) {
  return (Array.isArray(issues) ? issues : []).map((i) => {
    const github = i.source === "github";
    const who = github ? i.assignees?.[0]?.login ?? i.author?.login : i.assignee?.displayName ?? i.assignee?.name;
    return {
      kind: "issue",
      id: `issue:${github ? `github:${i.number}` : i.identifier}`,
      title: github ? `#${i.number} ${i.title}` : `${i.identifier} ${i.title}`,
      sub: who ?? "",
      state: github ? (i.state ?? "").toLowerCase() : i.state?.name ?? "",
      detail: shortLink(i.url),
      identifier: github ? null : i.identifier,
      ref: github ? `github:${i.number}` : `linear:${i.identifier}`,
      url: i.url,
    };
  });
}

// The layout commands that show the block running `mod`: pick it in each stack above it, and
// show each hidden node on the way. null: the layout has no such block.
export function reveal(root, mod) {
  const path = [];
  const walk = (node) => {
    path.push(node);
    if (node?.content?.mod === mod) return true;
    for (const child of node?.children ?? []) if (walk(child)) return true;
    path.pop();
    return false;
  };
  if (!root || !walk(root)) return null;
  const steps = [];
  path.forEach((node, k) => {
    if (node.type === "stack" && path[k + 1] && node.active !== path[k + 1].id) steps.push(["layout.select", { stack: node.id, child: path[k + 1].id }]);
  });
  for (const node of path) if (node.hidden && node.id) steps.push(["layout.show", { id: node.id }]);
  return steps;
}

// What `hc` is asked to send. No shell sees the message, which can hold anything typed.
export function message(text, file) {
  return file ? `${text}\n\nFile: ${file}` : text;
}
