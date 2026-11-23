// What the folder, Git and editors say, as plain data. No drawing and no side effects.
export const PER_FOLDER = 500;
export const TOTAL_ROWS = 5000;
export const MAX_CHARS = 400000;

// Editors found by app ID: a Nix or per-user install isn't in /Applications.
// More can be added under `settings.editors` in mod.json.
// bins: the editor's commands on Linux, first found wins. Arch names Zed's `zeditor`
// (with `zed` too), its own installer `zed`; Code - OSS builds name theirs `code-oss`.
export const EDITORS = [
  { name: "Zed", bundle: "dev.zed.Zed", exe: "Zed.exe", bins: ["zeditor", "zed"] },
  { name: "VS Code", bundle: "com.microsoft.VSCode", exe: "Code.exe", bins: ["code", "code-oss"] },
  { name: "Cursor", bundle: "com.todesktop.230313mzl4w4u92", exe: "Cursor.exe", bins: ["cursor"] },
  { name: "Windsurf", bundle: "com.exafunction.windsurf", exe: "Windsurf.exe", bins: ["windsurf"] },
  { name: "Sublime Text", bundle: "com.sublimetext.4", exe: "sublime_text.exe", bins: ["subl"] },
  // Nova is macOS-only, no Windows or Linux executable
  { name: "Nova", bundle: "com.panic.Nova" },
];

const LANGUAGES = {
  ts: "js",
  tsx: "js",
  mts: "js",
  cts: "js",
  jsx: "js",
  mjs: "js",
  cjs: "js",
  toml: "yaml",
  jsonc: "json",
  svelte: "html",
  vue: "html",
};

export const baseName = (path) => path.split("/").pop();
export const parentOf = (path) => path.slice(0, path.lastIndexOf("/")) || "/";

const extOf = (path) => {
  const name = baseName(path);
  return name.includes(".") ? name.split(".").pop().toLowerCase() : "";
};
const IMAGES = new Set(["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"]);
export const isImage = (path) => IMAGES.has(extOf(path));
export const isMarkdown = (path) => ["md", "markdown"].includes(extOf(path));

// A link or image source in a Markdown file as an absolute path, from the file's folder.
// Web addresses and other schemes aren't paths, so they come back null.
export function resolvePath(folder, link) {
  let rel = String(link ?? "").replace(/^file:\/\//, "");
  if (/^[a-z][a-z0-9+.-]*:/i.test(rel)) return null;
  rel = rel.replace(/[?#].*$/, "");
  try {
    rel = decodeURIComponent(rel);
  } catch {}
  if (!rel) return null;
  const parts = rel.startsWith("/") ? [""] : folder.split("/");
  for (const part of rel.split("/")) {
    if (part === "..") parts.length > 1 && parts.pop();
    else if (part && part !== ".") parts.push(part);
  }
  return parts.join("/") || "/";
}

// A code fence, at any indent (one in a list item is indented): its indent, its run of
// backticks or tildes, and what follows, the language.
const FENCE = /^(\s*)(`{3,}|~{3,})(.*)$/;
// `[label]: url "title"`, which reference links and images are resolved against.
// Front matter: `---` on a file's first line (a byte-order mark allowed) up to the next
// `---` or `...`. Only when empty or opening with a `key:` or a `#` comment, so a file that
// merely starts with a rule and some prose is left as it is.
const FRONT_OPEN = /^\uFEFF?---\s*$/;
const FRONT_CLOSE = /^(---|\.\.\.)\s*$/;
const FRONT_FIRST = /^\s*(#|["']?[\w.-]+["']?\s*:(\s|$))/;
export function frontMatter(source) {
  if (!FRONT_OPEN.test(source[0]?.replace(/\r$/, "") ?? "")) return null;
  const lines = [];
  for (let i = 1; i < source.length; i++) {
    const line = source[i].replace(/\r$/, "");
    if (FRONT_CLOSE.test(line)) {
      const first = lines.find((l) => l.trim());
      return first === undefined || FRONT_FIRST.test(first) ? { end: i, text: lines.join("\n") } : null;
    }
    lines.push(line);
  }
  return null;
}

export const REFERENCE = /^ {0,3}\[([^\]]+)\]:\s*<?([^\s>]+)>?(?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?\s*$/;
const HEADING = /^ {0,3}(#{1,6})\s+(.+?)\s*#*\s*$/;
const LIST_ITEM = /^([*+-]|\d{1,9}[.)])\s+/;

// The `#anchor` GitHub gives a heading: lower case, punctuation dropped, spaces as dashes.
// An underscore inside a word stays (`snake_case`); one marking emphasis (`_word_`) goes.
export function headingAnchor(title) {
  return String(title)
    .replace(/<[^>]*>/g, "")
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/[`*~]/g, "")
    .replace(/(^|[^\p{L}\p{N}_])_+|_+(?![\p{L}\p{N}_])/gu, "$1")
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s_-]/gu, "")
    .replace(/\s/g, "-");
}

const attribute = (tag, name) => new RegExp(`\\s${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, "i").exec(tag)?.slice(1).find((v) => v != null);
const pixels = (value) => (/^\d+$/.test(value ?? "") ? Number(value) : undefined);

// A line made only of pictures, as `{ items }`, or null when anything else is on it:
// `![alt](src)` and `![alt][ref]`, each maybe in a link (`[![alt](src)](href)`), and HTML
// `<img>`, maybe in `<a href>` or a wrapper such as `<p>`. Markdown images must start the
// line (or follow a list marker, kept as `bullet`); an indented one is code or belongs to the
// item above. HTML may be indented, as it is inside a `<div>`.
export function imageLine(line, refs, folder) {
  let rest = line.replace(/\r$/, "");
  const html = /^\s*</.test(rest);
  let bullet = false;
  const marker = LIST_ITEM.exec(rest);
  if (marker) {
    bullet = true;
    rest = rest.slice(marker[0].length);
  } else if (!html && /^\s/.test(rest)) return null;
  const items = [];
  let href = null;
  const source = (src) => {
    const link = String(src ?? "").trim();
    if (/^https?:\/\//i.test(link)) return { url: link };
    const path = resolvePath(folder, link);
    return path && isImage(path) ? { path } : null;
  };
  const MD = /!\[([^\]]*)\](?:\(\s*(?:<([^>]*)>|([^)\s]+))(?:\s+"[^"]*")?\s*\)|\[([^\]]*)\])/y;
  const LINK_END = /\](?:\(\s*(?:<([^>]*)>|([^)\s]+))(?:\s+"[^"]*")?\s*\)|\[([^\]]*)\])/y;
  let at = 0;
  const sticky = (pattern) => {
    pattern.lastIndex = at;
    const match = pattern.exec(rest);
    if (match) at = pattern.lastIndex;
    return match;
  };
  const markdownImage = () => {
    const m = sticky(MD);
    if (!m) return null;
    const src = m[4] != null ? refs.get((m[4] || m[1]).toLowerCase()) : (m[2] ?? m[3]);
    return { alt: m[1], ...source(src) };
  };
  while (at < rest.length) {
    if (sticky(/\s+/y)) continue;
    if (rest[at] === "[" && rest[at + 1] === "!") {
      at++;
      const item = markdownImage();
      const end = item && sticky(LINK_END);
      if (!end) return null;
      items.push({ ...item, href: end[3] != null ? refs.get(end[3].toLowerCase()) ?? null : (end[1] ?? end[2]) });
      continue;
    }
    if (rest[at] === "!") {
      const item = markdownImage();
      if (!item) return null;
      items.push({ ...item, href });
      continue;
    }
    if (!html && !bullet && rest[at] === "<") return null;
    const tag = sticky(/<[^>]*>/y);
    if (!tag) return null;
    const name = /^<\/?([a-z]+)/i.exec(tag[0])?.[1]?.toLowerCase();
    if (name === "img") {
      const src = source(attribute(tag[0], "src"));
      items.push({ alt: attribute(tag[0], "alt") ?? "", ...src, href, width: pixels(attribute(tag[0], "width")), height: pixels(attribute(tag[0], "height")) });
    } else if (name === "a") href = tag[0].startsWith("</") ? null : (attribute(tag[0], "href") ?? null);
    else if (!["p", "div", "span", "center", "picture", "source", "br"].includes(name)) return null;
  }
  // One that can't be drawn (a PDF, a missing reference, a `data:` source) leaves the whole
  // line to TextView, so nothing on it is lost.
  if (!items.length || items.some((item) => !item.path && !item.url)) return null;
  return { bullet, items };
}

// Markdown as blocks for the preview. Herdr's TextView draws the text, split at each heading so
// an `#anchor` link can reach it (`anchor`), with the file's reference definitions added to
// every piece so its reference links still resolve. Code fences become code blocks the viewer
// draws itself. A line of pictures becomes an image block: one plain image as `image`, else
// `images`, consecutive lines in one block, a row each. Pictures inside a paragraph, a quote
// or under a list item are left to TextView. Front matter comes first as a `yaml` code block,
// as GitHub shows it apart from the text: TextView would draw its `---` as a rule and the
// YAML as one long heading.
export function markdownBlocks(text, folder) {
  const all = String(text ?? "").split("\n");
  const front = frontMatter(all);
  const source = front ? all.slice(front.end + 1) : all;
  const refs = new Map();
  const definitions = [];
  let fence = null;
  for (const line of source) {
    const opens = FENCE.exec(line);
    if (fence) {
      if (opens && opens[2][0] === fence[0] && opens[2].length >= fence.length && !opens[3].trim()) fence = null;
      continue;
    }
    if (opens) {
      fence = opens[2];
      continue;
    }
    const ref = REFERENCE.exec(line);
    if (ref) {
      refs.set(ref[1].toLowerCase(), ref[2]);
      definitions.push(line);
    }
  }
  const appendix = definitions.length ? `\n\n${definitions.join("\n")}` : "";
  const seen = new Map();
  const blocks = front ? [{ type: "code", lang: "yaml", text: front.text }] : [];
  let lines = [];
  let anchor = null;
  const flush = () => {
    if (lines.some((line) => line.trim() && !REFERENCE.test(line))) {
      const block = { type: "text", text: lines.join("\n") + appendix };
      if (anchor) block.anchor = anchor;
      blocks.push(block);
    }
    lines = [];
    anchor = null;
  };
  let code = null;
  for (const line of source) {
    if (code) {
      const closes = FENCE.exec(line);
      if (closes && closes[2][0] === code.fence[0] && closes[2].length >= code.fence.length && !closes[3].trim()) {
        blocks.push({ type: "code", lang: code.lang, text: code.lines.join("\n") });
        code = null;
      } else code.lines.push(line.replace(/\r$/, "").replace(new RegExp(`^ {0,${code.indent}}`), ""));
      continue;
    }
    const opens = FENCE.exec(line);
    if (opens && !(opens[2][0] === "`" && opens[3].includes("`"))) {
      flush();
      code = { fence: opens[2], indent: opens[1].length, lang: opens[3].trim().split(/[\s{,]/)[0], lines: [] };
      continue;
    }
    const heading = HEADING.exec(line);
    if (heading) {
      flush();
      const base = headingAnchor(heading[2]);
      const n = seen.get(base) ?? 0;
      seen.set(base, n + 1);
      anchor = n ? `${base}-${n}` : base;
    }
    const row = !heading && imageLine(line, refs, folder);
    if (row) {
      flush();
      const last = blocks.at(-1);
      if (last?.type === "images") last.rows.push(row);
      else blocks.push({ type: "images", rows: [row] });
      continue;
    }
    lines.push(line);
  }
  if (code) blocks.push({ type: "code", lang: code.lang, text: code.lines.join("\n") });
  flush();
  // One plain picture on its own stays the simple shape the viewer has always drawn.
  return blocks.map((block) => {
    const only = block.type === "images" && block.rows.length === 1 && block.rows[0].items.length === 1 && !block.rows[0].bullet ? block.rows[0].items[0] : null;
    return only && !only.href && !only.width && !only.height ? { type: "image", alt: only.alt, ...(only.path ? { path: only.path } : { url: only.url }) } : block;
  });
}

export function languageOf(path) {
  const name = baseName(path);
  const ext = name.includes(".") ? name.split(".").pop() : "txt";
  return LANGUAGES[ext] ?? ext;
}

// Directories first, each kind by name, the way a file browser reads.
export function sortEntries(entries) {
  return [...entries].sort(
    (a, b) => Number(b.dir) - Number(a.dir) || a.name.localeCompare(b.name),
  );
}

// `git status --porcelain=v1 -z`, keyed by absolute path. `staged` is true when the only
// change is in the index, which is where a diff of it has to look.
// How a path is compared: Git writes forward slashes and its own drive-letter case even on
// Windows, while the tree keeps the folder's own spelling, so marks are stored and looked up
// by this key. A POSIX path comes out unchanged unless its names hold a backslash.
export const markKey = (path) => path.replace(/\\/g, "/").replace(/^[A-Z]:/, (d) => d.toLowerCase());

export function parseStatus(stdout, top) {
  const marks = {};
  for (const entry of stdout.split("\0").filter(Boolean).slice(0, TOTAL_ROWS)) {
    const xy = entry.slice(0, 2);
    const untracked = xy === "??";
    marks[markKey(`${top}/${entry.slice(3)}`)] = {
      mark: untracked || xy.includes("A") ? "A" : xy.includes("U") ? "U" : xy.includes("D") ? "D" : "M",
      staged: !untracked && xy[0] !== " " && xy[1] === " ",
    };
  }
  return marks;
}

// `git diff -U0` as changes, by 0-based line in the file as it is now, each with the old
// lines it replaced. A hunk with new lines and none removed is added; with both, changed;
// with only removed lines, there's no line to colour, so it marks the place they were.
export function parseHunks(diff) {
  const hunks = [];
  let current = null;
  for (const text of diff.split("\n")) {
    const header = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(text);
    if (header) {
      const [, oldStart, removed, start, added] = header;
      const gone = removed === undefined ? 1 : Number(removed);
      const fresh = added === undefined ? 1 : Number(added);
      current = {
        line: fresh ? Number(start) - 1 : Number(start),
        count: fresh,
        kind: !fresh ? "removed" : gone ? "changed" : "added",
        oldStart: Number(oldStart),
        old: [],
      };
      hunks.push(current);
    } else if (current && text.startsWith("-")) current.old.push(text.slice(1));
  }
  return hunks;
}

export function expandTabs(line) {
  let column = 0;
  let out = "";
  for (const char of line.replace(/\r$/, "")) {
    if (char === "\t") {
      const spaces = 4 - (column % 4);
      out += " ".repeat(spaces);
      column += spaces;
    } else {
      out += char;
      column++;
    }
  }
  return out;
}
const cleanLine = expandTabs;
export const fileLinesOf = (text) => text.split("\n").map(cleanLine);

// What to draw, top to bottom: the file's lines, and where a change is open, the lines it
// replaced. A closed removal is a thin row of its own, so it can be clicked without a line.
export function buildRows(lines, hunks, open) {
  const covering = new Map();
  const startingAt = new Map();
  const removedAt = new Map();
  for (const hunk of hunks) {
    if (hunk.kind === "removed") removedAt.set(Math.min(hunk.line, lines.length), hunk);
    else {
      startingAt.set(hunk.line, hunk);
      for (let i = hunk.line; i < Math.min(hunk.line + (hunk.count ?? lines.length), lines.length); i++)
        covering.set(i, hunk);
    }
  }
  const rows = [];
  const oldRows = (hunk) =>
    hunk.old.forEach((text, n) =>
      rows.push({
        key: `old-${hunk.oldStart + n}`,
        type: "old",
        number: hunk.oldStart + n,
        text: cleanLine(text),
        hunk,
      }),
    );
  for (let i = 0; i <= lines.length; i++) {
    const removal = removedAt.get(i);
    if (removal) {
      if (open.has(hunkKey(removal))) oldRows(removal);
      else rows.push({ key: `removed-${i}`, type: "removed", hunk: removal });
    }
    const starting = startingAt.get(i);
    if (starting && open.has(hunkKey(starting))) oldRows(starting);
    if (i < lines.length)
      rows.push({ key: `line-${i}`, type: "line", number: i + 1, text: lines[i], hunk: covering.get(i) });
  }
  return rows;
}

export const hunkKey = (hunk) => `${hunk.kind}-${hunk.oldStart}`;

// A folder holds a change if any changed file is inside it.
export const holdsChange = (marks, folder) => {
  const prefix = `${markKey(folder)}/`;
  return Object.keys(marks).some((path) => path.startsWith(prefix));
};

// Read-only view text: what can't be shown says why.
export function viewable(text) {
  if (text === null) return { problem: "This file is no longer available." };
  if (text.includes("\0")) return { problem: "This is a binary file, so there's no text to show." };
  return text.length > MAX_CHARS
    ? { text: `${text.slice(0, MAX_CHARS)}\n… (file truncated)` }
    : { text };
}
