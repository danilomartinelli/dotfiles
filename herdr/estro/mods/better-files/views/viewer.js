// A file in the centre pane, read-only, following the file as it changes on disk. Editing
// belongs in the code editor it can open.
import { div, image } from "gpui-kit";
import { h_flex, v_flex, Editor, EditorState, Scrollbar, v_virtual_list } from "gpui-base";
import { appHome, exec, focused, layout, panes, readTextFile, setShared, shared, theme, window } from "herdr";
import {
  baseName,
  buildRows,
  fileLinesOf,
  hunkKey,
  isImage,
  isMarkdown,
  REFERENCE,
  languageOf,
  markdownBlocks,
  parentOf,
  parseHunks,
  resolvePath,
  viewable,
} from "../files/model.js";
import { WHOLE_FILE_LINES, fenceLanguage, languageOf as lexerLanguage, syntaxColors, tokenizeLine } from "../syntax.js";
import { viewerEntries } from "../actions/open.js";
import { BUSY, pickCopyImage, pickFetchImage, pickRm } from "../files/shell.js";
import { editorId, foundEditors } from "../actions/outside.js";
import { fileIcon, isLight } from "../files/file-icons.js";
import { TEXT, FileIcon, IconButton, Markdown, Message, MenuButton, TextButton, codeFont, codeSize } from "./ui.js";

const CHAR_WIDTH = 0.62; // Of the code font's size, to size the sideways scroll.
const LINE_COLUMNS = 6; // The number column and a margin, in the same units.
const rowHeight = () => Math.round(codeSize() * 1.6);
const REMOVED_ROW = 8;
const COLOR_CHARS = 4000;
const COLOR_TICK_MS = 16;

// Copies go in a hidden folder: saving any other file in a mod's folder makes Herdr reload
// the mod, which threw the tree away on every picture opened. The copy itself, and how it's
// named, is in files/shell.js.
const CACHE = "mods/better-files/.cache";
const extension = (path) => path.split(".").pop().toLowerCase();
const absolute = (copy) => (copy ? `${appHome()}/${copy}` : "");
const COPIED_MS = 1500;

// A short, stable name for a web address, so the same badge is one file in the cache.
const webName = (url) => {
  let hash = 2166136261;
  for (let i = 0; i < url.length; i++) hash = Math.imul(hash ^ url.charCodeAt(i), 16777619);
  return `web-${(hash >>> 0).toString(16)}`;
};

export const viewerMethods = {
  // What this tab shows: the registry, then what it was opened with, after a restart.
  viewerEntry() {
    return viewerEntries()[this.viewerId] ?? null;
  },

  // Runs as the tab opens, which is when the focused tab is its own.
  claimTab() {
    const entry = this.viewerEntry();
    const where = this.tabSpaces();
    const holds = (other) => Boolean(other.tab) && !this.wrongTab(other, where);
    // A tab recorded from another space isn't this one, so it keeps looking for its own.
    if (entry && holds(entry)) return;
    const space = entry?.space ?? this.viewerSpace;
    const tab = focused()?.tab;
    if (!tab || !panes().some((p) => p.tab === tab && p.mod === "better-files")) return;
    // Focus can sit in another space while this tab opens; that space's tab isn't this one.
    if ((where.get(tab) ?? space) !== space) return;
    const rest = Object.entries(viewerEntries()).filter(([id]) => id !== this.viewerId).map(([, other]) => other);
    // A tab reopened behind another one must not take that one's place.
    if (rest.some((other) => holds(other) && other.tab === tab)) return;
    if (entry?.others?.includes(tab)) return;
    // Nor may it take the tab of a viewer here asked for after it, which hasn't claimed one yet.
    const unclaimed = (other) => (other.tab ? !holds(other) : this.viewerIsLive(other));
    const newer = (other) => other.space === space && (other.at ?? 0) > (entry?.at ?? 0) && unclaimed(other);
    if (rest.some((other) => newer(other) && other.others && !other.others.includes(tab))) return;
    // A click skips a viewer while its tab is wrong, so the space may have a new shared tab
    // by now; then this one becomes a tab you keep, leaving one shared tab per space.
    const sharedHere = rest.some(
      (other) => other.space === space && other.preview && this.viewerIsLive(other) && !this.wrongTab(other, where),
    );
    this.setViewer(this.viewerId, {
      tab,
      space,
      file: entry?.file ?? this.viewerFile,
      preview: (entry?.preview ?? false) && !sharedHere,
    });
  },

  syncViewer(cx) {
    this.retryCleanup(cx);
    this.claimTab();
    const file = this.viewerEntry()?.file ?? this.viewerFile;
    if (!file) return;
    if (file.path !== this.file?.path || file.root !== this.file?.root || file.on !== this.file?.on) {
      this.file = { ...file };
      this.imageShown = null;
      this.imageFor = null;
      this.reading = null;
      this.diffing = null;
      this.text = undefined;
      this.problem = null;
      this.code?.release();
      this.code = null;
      this.hunks = [];
      this.openHunks = new Set();
      this.readFile(cx);
      this.readHunks(cx);
      cx.notify();
    }
    this.publishHead();
    this.colorStep(cx);
  },

  // Asked on every check, not just when the text changes: a commit clears marks without
  // touching the file.
  readHunks(cx) {
    const file = this.file;
    if (!file || !this.gutterOn || this.diffing || isImage(file.path)) return;
    this.diffing = file;
    cx.spawn(async (cx) => {
      const git = (args) =>
        exec("git", ["--no-optional-locks", ...args], { cwd: file.root, on: file.on }).catch(() => null);
      let marks = [];
      const status = await git(["status", "--porcelain=v1", "--", file.path]);
      if (status?.code === 0 && status.stdout.startsWith("??")) {
        marks = [{ line: 0, count: Infinity, kind: "added", oldStart: 0, old: [] }];
      } else if (status?.code === 0 && status.stdout.trim()) {
        const diff = await git(["diff", "--no-color", "--no-ext-diff", "--no-textconv", "-U0", "HEAD", "--", file.path]);
        if (diff?.code === 0) marks = parseHunks(diff.stdout);
      }
      if (this.diffing === file) this.diffing = null;
      if (this.file !== file) return;
      if (JSON.stringify(marks) !== JSON.stringify(this.hunks)) {
        this.hunks = marks;
        cx.notify();
      }
    });
  },

  // Only a real change touches the view, so the place you're reading stays put.
  readFile(cx) {
    if (this.closed) return;
    const file = this.file;
    if (file && isImage(file.path)) return this.readImage(cx);
    if (!file || this.reading) return;
    this.reading = file;
    cx.spawn(async (cx) => {
      let shown;
      try {
        shown = viewable(await readTextFile(file.path, { on: file.on }));
      } catch {
        shown = { problem: "This file can't be shown: it's too large, or can't be read." };
      }
      if (this.reading === file) this.reading = null;
      if (this.file !== file) return;
      if (shown.problem) {
        this.problem = shown.problem;
        this.text = undefined;
        this.code?.release();
        this.code = null;
      } else if (shown.text !== this.text) {
        this.problem = null;
        this.text = shown.text;
        if (!this.gutterOn) {
          if (this.code) this.code.set_value(shown.text);
          else this.code = this.newCode(file, shown.text);
        }
      }
      this.readMarkdownImages(cx);
      cx.notify();
    });
  },

  newCode(file, value) {
    const t = theme();
    return EditorState.new({
      language: languageOf(file.path),
      readonly: true,
      value,
      font_family: codeFont(),
      font_size: codeSize(),
      syntax: {
        keyword: t.ansi5,
        string: t.ansi2,
        comment: t.dim,
        function: t.ansi4,
        type: t.ansi3,
        number: t.ansi1,
        constant: t.ansi6,
        boolean: t.ansi6,
        operator: t.ansi6,
        "string.escape": t.ansi6,
      },
    });
  },

  // What the pane's header row says, the same row a diff uses: file, folder, and whether
  // this is the shared tab.
  viewerHead() {
    const file = this.file;
    if (!file) return null;
    const name = baseName(file.path);
    const folder = file.path.slice(file.root.length + 1, -name.length - 1);
    const picture = fileIcon(this.fileIcons, file.path, { light: isLight(theme().background) });
    return {
      title: name,
      detail: [folder, this.viewerEntry()?.preview ? "Preview" : null].filter(Boolean).join(" · "),
      // color: a full-colour picture, which Better Changes' pane header draws untinted.
      ...(picture ? { icon: picture, color: true } : { icon: "mods/better-files/icons/file.svg" }),
    };
  },

  publishHead() {
    // Never onto a tab in another space: that one has its own viewer.
    const entry = this.viewerEntry();
    const tab = entry && !this.wrongTab(entry) ? entry.tab : null;
    const pane = tab && panes().find((p) => p.mod === "better-files" && p.tab === tab)?.pane;
    const head = this.viewerHead();
    if (!pane || !head) return;
    const heads = shared("pane-heads") ?? {};
    if (JSON.stringify(heads[pane]) !== JSON.stringify(head))
      setShared("pane-heads", { ...heads, [pane]: head });
  },

  // Better Changes' pane header shows a published title. With any other header, the file
  // draws its own row, so there's always exactly one.
  headerShowsTitle() {
    const find = (node) =>
      node?.content?.pane?.header?.content?.mod ?? (node?.children ?? []).map(find).find(Boolean);
    return find(layout()) === "better-changes";
  },

  // The file as rows, the way Better Changes draws a diff. Herdr's editor can't mark a line,
  // and marks laid over it slid as it scrolled, but here a line's colour is part of its row.
  linesView() {
    const lines = this.fileLines();
    const runs = this.lineRuns(lines);
    const rows = buildRows(lines, this.hunks ?? [], this.openHunks);
    const height = rowHeight();
    const sized = rows.some((row) => row.type === "removed")
      ? rows.map((row) => (row.type === "removed" ? REMOVED_ROW : height))
      : height;
    const listId = `viewer-lines-${this.viewerId}-${this.file.path}`;
    const list = v_virtual_list(
      listId,
      rows.length,
      sized,
      (i) => rows[i].key,
      (range) => rows.slice(range.start, range.end).map((row) => this.fileRow(row, runs)),
    )
      // A handler per list, not per row: Herdr's virtual lists allow no handlers in a row.
      .on_item_click((key, cx) => this.toggleChange(rows.find((row) => row.key === key), cx))
      .size_full();
    const widest = lines.reduce((most, line) => Math.max(most, line.length), 0);
    return div()
      .id("viewer-lines")
      .flex_1()
      .min_h(0)
      .min_w(0)
      .relative()
      .font_family(codeFont())
      .text_size(codeSize())
      .child(
        div()
          .id("viewer-x")
          .size_full()
          .overflow_x_scrollbar()
          .child(
            div()
              .w_full()
              .min_w(Math.max(300, (widest * CHAR_WIDTH + LINE_COLUMNS) * codeSize()))
              .h_full()
              .child(list),
          ),
      )
      .child(Scrollbar.vertical(listId).viewport_from_layout().absolute().inset_0());
  },

  // Only a change that replaced something has anything to open.
  toggleChange(row, cx) {
    if (!row?.hunk?.old.length) return;
    const key = hunkKey(row.hunk);
    if (!this.openHunks.delete(key)) this.openHunks.add(key);
    cx.notify();
  },

  // Split once per version of the file: rows are drawn on every scroll.
  fileLines() {
    if (this.linesOf !== this.text) {
      this.linesOf = this.text;
      this.lines = fileLinesOf(this.text ?? "");
    }
    return this.lines;
  },

  // Coloured once per version too, top to bottom, so a comment or string opened on one
  // line is still one on the next, in steps by `colorStep`. Until those finish, and for a
  // huge file or one the lexer fails on, there are no runs here: rows are coloured one at a
  // time as they're drawn (`rowRuns`). The runs are kept only once they're complete, so a row
  // never shows another file's text.
  lineRuns(lines) {
    // Keyed on the path too: two files with the same text share `lines`, not a language.
    if (this.runsFor !== lines || this.runsPath !== this.file.path) {
      const path = this.file.path;
      this.runs = null;
      this.runsFor = lines;
      this.runsPath = path;
      if (lines.length <= WHOLE_FILE_LINES)
        this.colorLater(lines, lexerLanguage(path), {
          live: () => this.runsFor === lines && this.runsPath === path,
          done: (runs) => (this.runs = runs),
        });
    }
    return this.runs;
  },

  colorLater(lines, language, { live, done }) {
    (this.colorJobs ??= []).push({ lines, language, live, done, runs: [], state: null });
  },

  colorStep(cx) {
    const jobs = this.colorJobs;
    if (this.colorQueued || !jobs?.length) return;
    let budget = COLOR_CHARS;
    while (budget > 0 && jobs.length) {
      const job = jobs[0];
      if (!job.live()) {
        jobs.shift();
        continue;
      }
      try {
        while (budget > 0 && job.runs.length < job.lines.length) {
          const line = job.lines[job.runs.length];
          const result = tokenizeLine(line, job.language, job.state);
          job.state = result.state;
          job.runs.push(result.runs);
          budget -= line.length + 1;
        }
      } catch {
        jobs.shift();
        continue;
      }
      if (job.runs.length < job.lines.length) break;
      jobs.shift();
      job.done(job.runs);
      cx.notify();
    }
    if (!jobs.length) return;
    this.colorQueued = true;
    cx.timer.after(COLOR_TICK_MS, (cx) => {
      this.colorQueued = false;
      this.colorStep(cx);
    });
  },

  // One row's runs: from the whole-file pass when there is one, else that line on its own.
  rowRuns(row, lineRuns) {
    const runs = lineRuns?.[row.number - 1];
    if (runs) return runs;
    try {
      return tokenizeLine(row.text, lexerLanguage(this.file.path)).runs;
    } catch {
      return [{ text: row.text, kind: null }];
    }
  },

  fileRow(row, lineRuns) {
    const t = theme();
    if (row.type === "removed")
      return h_flex()
        .id(`viewer-${row.key}`)
        .h(REMOVED_ROW)
        .w_full()
        .items_center()
        .cursor_pointer()
        .child(div().h(2).w_full().bg(t.ansi1));
    const old = row.type === "old";
    const open = row.hunk && this.openHunks.has(hunkKey(row.hunk));
    // A line whose old version is showing reads as what replaced it.
    const color = old
      ? t.ansi1
      : row.hunk
        ? { added: t.ansi2, changed: open ? t.ansi2 : t.ansi3 }[row.hunk.kind]
        : null;
    const SYNTAX = syntaxColors(t);
    const runs = old ? [{ text: row.text, kind: "old" }] : this.rowRuns(row, lineRuns);
    return h_flex()
      .id(`viewer-${row.key}`)
      .h(rowHeight())
      .w_full()
      .items_center()
      .when(Boolean(color), (el) => el.bg(`${color?.slice(0, 7)}26`))
      .when(Boolean(row.hunk?.old.length), (el) => el.cursor_pointer())
      .child(
        div()
          .id(color && !old ? `viewer-mark-${row.number - 1}` : `viewer-bar-${row.key}`)
          .w(3)
          .h_full()
          .flex_none()
          .when(Boolean(color), (el) => el.bg(color)),
      )
      .child(
        div()
          .w(codeSize() * 3.5)
          .pr(codeSize())
          .flex_none()
          .text_right()
          .text_color(t.dim)
          .child(String(row.number)),
      )
      .child(
        h_flex()
          .flex_1()
          .min_w(0)
          .whitespace_nowrap()
          .children(
            runs.map((run) =>
              div()
                .flex_none()
                .whitespace_nowrap()
                .text_color(run.kind === "old" ? t.ansi1 : (SYNTAX[run.kind] ?? t.foreground))
                .child(run.text || " "),
            ),
          ),
      );
  },

  // Removes copies this tab made, given as paths under Herdr's folder.
  async dropCopies(copies) {
    if (!copies.length) return true;
    let removed = true;
    for (let i = 0; i < copies.length; i += 32) {
      const { program, args } = pickRm(copies.slice(i, i + 32).map(absolute), window()?.platform);
      const result = await exec(program, args, { timeout: 10000 }).catch(() => null);
      if (result?.code !== 0) removed = false;
    }
    return removed;
  },

  // Herdr only loads images from under its own folder, so the file is shown through a copy
  // in this mod's cache, named for what's in it. The copy it replaces goes once it's in.
  readImage(cx) {
    if (this.closed) return;
    const file = this.file;
    if (file.on || this.imageReading) return;
    if (this.imageFor !== file.path) {
      this.imageFor = file.path;
      this.imageShown = null;
    }
    this.imageReading = file;
    cx.spawn(async (cx) => {
      const { program, args } = pickCopyImage(file.path, absolute(CACHE), this.viewerId, extension(file.path), absolute(this.imageCopy), window()?.platform, Boolean(this.imageCopy));
      const result = await exec(program, args, { timeout: 10000 }).catch(() => null);
      const copy = result?.code === 0 ? `${CACHE}/${result.stdout.trim()}` : null;
      if (copy) {
        this.imageCopies ??= new Set();
        this.imageCopies.add(copy);
      }
      if (!this.closed && this.file === file && result?.code !== BUSY) {
        const problem = copy ? null : `This file is no longer available: ${file.path}`;
        if (problem !== this.problem || copy !== this.imageShown) {
          this.problem = problem;
          this.imageShown = copy;
          cx.notify();
        }
      }
      const obsolete = [...(this.imageCopies ?? [])].filter(path => this.closed || path !== this.imageShown);
      const batch = obsolete.slice(0, 32);
      const deferred = obsolete.slice(32);
      for (const path of batch) {
        const removed = await this.dropCopies([path]);
        this.imageCopies.delete(path);
        if (!removed) {
          if (this.closed) deferred.push(path);
          else this.imageCopies.add(path);
        }
      }
      this.queueCleanup(deferred);
      for (const path of deferred) this.imageCopies.delete(path);
      this.imageCopy = this.imageShown;
      if (this.imageReading === file) this.imageReading = null;
      if (this.closed) this.releaseCacheOwner();
      if (!this.closed && this.file !== file && this.file && isImage(this.file.path)) this.readImage(cx);
    });
  },

  // Another machine's file isn't on this one to load.
  imageView() {
    if (this.file.on) return Message("Images on another machine can't be shown here.");
    if (this.problem) return Message(this.problem);
    if (!this.imageShown) return Message("Loading…");
    return h_flex()
      .id("viewer-image")
      .flex_1()
      .min_h(0)
      .min_w(0)
      .p(16)
      .child(image(this.imageShown).flex_1().min_w(0).h_full());
  },

  // Preview or Code, chosen per tab and kept in the registry, else the setting.
  markdownView() {
    return this.viewerEntry()?.markdown ?? this.markdownDefault ?? "preview";
  },

  showsPreview() {
    return Boolean(this.file && isMarkdown(this.file.path)) && this.markdownView() === "preview";
  },

  // Split once per version of the file, like the code view's lines.
  previewBlocks() {
    const key = `${this.file.path}\0${this.text}`;
    if (this.blocksOf !== key) {
      this.blocksOf = key;
      this.blocks = markdownBlocks(this.text ?? "", parentOf(this.file.path));
    }
    return this.blocks;
  },

  // Every picture a Markdown file shows, on its own line or in a row.
  markdownSources() {
    return this.previewBlocks().flatMap((block) =>
      block.type === "image" ? [block] : block.type === "images" ? block.rows.flatMap((row) => row.items) : [],
    );
  },

  // A Markdown file's pictures, copied into the cache the way the image viewer does. One from
  // this computer gets a name of its own for as long as the tab is open, and is checked whenever
  // the file is. The last copy stays on screen until the new one is in: a name shown before its
  // file is there would stay blank, as Herdr doesn't see the hidden folder change. One from the
  // web is downloaded once per tab, and kept for a day under a name of its address, so every
  // tab shares it.
  readMarkdownImages(cx) {
    if (this.closed) return;
    const file = this.file;
    if (!file || !isMarkdown(file.path) || this.text === undefined) return;
    this.markdownCopies ??= new Map();
    this.markdownShown ??= new Map();
    this.markdownCopying ??= new Set();
    this.markdownSlots ??= new Map();
    for (const { path, url } of this.markdownSources()) {
      const key = url ?? path;
      if (!key || this.markdownCopying.has(key) || (path && file.on) || (url && this.markdownShown.has(key))) continue;
      this.markdownCopying.add(key);
      if (url) {
        const base = absolute(`${CACHE}/${webName(url)}`);
        cx.spawn(async (cx) => {
          const { program, args } = pickFetchImage(url, base, window()?.platform);
          const result = await exec(program, args, {}).catch(() => null);
          this.markdownCopying.delete(key);
          const copy = result?.code === 0 ? result.stdout.trim() : "";
          if (copy.startsWith(`${appHome()}/`)) this.markdownCopies.set(key, copy.slice(appHome().length + 1));
          this.markdownShown.set(key, this.markdownCopies.has(key));
          cx.notify();
        });
        continue;
      }
      if (!this.markdownSlots.has(path)) this.markdownSlots.set(path, this.markdownSlots.size + 1);
      const start = `${this.viewerId}-m${this.markdownSlots.get(path)}`;
      this.markdownLocalPending ??= new Set();
      this.markdownLocalPending.add(path);
      cx.spawn(async (cx) => {
        const old = this.markdownCopies.get(path);
        const { program, args } = pickCopyImage(path, absolute(CACHE), start, extension(path), absolute(old), window()?.platform);
        const result = await exec(program, args, { timeout: 10000 }).catch(() => null);
        this.markdownCopying.delete(path);
        this.markdownLocalPending.delete(path);
        if (result?.code === BUSY) return;
        const copy = result?.code === 0 ? `${CACHE}/${result.stdout.trim()}` : null;
        if (copy && this.closed) {
          if (!(await this.dropCopies([copy]))) this.queueCleanup([copy]);
          return;
        }
        if (copy) this.markdownCopies.set(path, copy);
        if (this.markdownShown.get(path) !== Boolean(copy) || copy !== old) {
          this.markdownShown.set(path, Boolean(copy));
          cx.notify();
        }
      });
    }
  },

  // A web link opens in the browser, a link to a file here opens it like a click in the tree,
  // and `#anchor` scrolls to the heading it names. Other schemes do nothing.
  followLink(url, cx) {
    if (/^https?:\/\//i.test(url)) return cx.open_url(url);
    if (url.startsWith("#")) {
      let anchor = url.slice(1);
      try {
        anchor = decodeURIComponent(anchor);
      } catch {}
      const index = this.previewBlocks().findIndex((block) => block.anchor === anchor.toLowerCase());
      if (index >= 0) {
        this.previewScroll?.scroll_to_item(index);
        cx.notify();
      }
      return;
    }
    const file = this.file;
    const path = resolvePath(parentOf(file.path), url);
    if (!path || path === file.path) return;
    const root = path.startsWith(`${file.root}/`) ? file.root : parentOf(path);
    this.openFile({ path, root, on: file.on ?? null }, cx);
  },

  // One picture. In a row (`small`), one that's loading or missing shows its name in small
  // dim text instead of a message, so a row of badges stays a row.
  previewImage(item, id, small = false) {
    const t = theme();
    const name = item.alt || baseName(item.path ?? item.url);
    const note = (text) => (small ? div().flex_none().text_size(TEXT.caption).text_color(t.dim).child(text) : Message(text));
    if (item.path && this.file.on) return note(`${name}: images on another machine can't be shown here.`);
    const key = item.url ?? item.path;
    const shown = this.markdownShown?.get(key);
    if (shown === false) return note(small ? name : `${name} isn't available.`);
    if (!shown) return note(small ? name : "Loading…");
    const picture = image(this.markdownCopies.get(key))
      .flex_none()
      .max_w_full()
      .when(Boolean(item.width), (el) => el.w(item.width))
      .when(Boolean(item.height), (el) => el.h(item.height));
    if (!item.href) return picture;
    return div()
      .id(id)
      .flex_none()
      .cursor_pointer()
      .tooltip(item.href)
      .on_click((_e, cx) => this.followLink(item.href, cx))
      .child(picture);
  },

  // Lines of pictures, a row each: badges side by side, and a bullet where they were a list.
  previewImages(block, i) {
    const t = theme();
    return v_flex()
      .id(`viewer-images-${i}`)
      .w_full()
      .min_w(0)
      .flex_none()
      .gap(6)
      .children(
        block.rows.map((row, r) =>
          h_flex()
            .w_full()
            .min_w(0)
            .flex_wrap()
            .gap(6)
            .items_center()
            .when(row.bullet, (el) => el.child(div().flex_none().w(14).text_color(t.dim).child("•")))
            .children(row.items.map((item, n) => this.previewImage(item, `viewer-image-${i}-${r}-${n}`, true))),
        ),
      );
  },

  // A fenced block, drawn here rather than by TextView: the code font at the terminals' size,
  // the lexer's colours, the language at the top left and a copy button at the top right.
  previewCode(block, i) {
    const t = theme();
    const SYNTAX = syntaxColors(t);
    const lines = block.text.split("\n");
    if (!block.runs && !block.queued) {
      block.queued = true;
      if (lines.length <= WHOLE_FILE_LINES)
        this.colorLater(lines, fenceLanguage(block.lang), {
          live: () => this.blocks?.includes(block),
          done: (runs) => (block.runs = runs),
        });
    }
    const blockRuns = block.runs ?? lines.map((line) => [{ text: line, kind: null }]);
    const widest = lines.reduce((n, line) => Math.max(n, line.length), 0);
    const copied = this.copiedCode === i;
    return v_flex()
      .id(`viewer-code-${i}`)
      .w_full()
      .min_w(0)
      .flex_none()
      .rounded(6)
      .border_1()
      .border_color(t.border)
      .bg(t.raised)
      .child(
        h_flex()
          .h(26)
          .pl(10)
          .pr(2)
          .items_center()
          .justify_between()
          .child(div().text_size(TEXT.caption).text_color(t.dim).child(block.lang || " "))
          .child(
            IconButton({
              id: `viewer-code-copy-${i}`,
              icon: copied ? "check" : "copy",
              label: copied ? "Copied" : "Copy code",
              small: true,
              onClick: (cx) => {
                cx.write_to_clipboard(block.text);
                this.copiedCode = i;
                cx.timer.after(COPIED_MS, (cx) => {
                  if (this.copiedCode !== i) return;
                  this.copiedCode = null;
                  cx.notify();
                });
                cx.notify();
              },
            }),
          ),
      )
      .child(
        div()
          .id(`viewer-code-lines-${i}`)
          .w_full()
          .overflow_x_scrollbar()
          .px(10)
          .pb(8)
          .child(
            v_flex()
              .min_w(Math.ceil(widest * CHAR_WIDTH * codeSize()))
              .font_family(codeFont())
              .text_size(codeSize())
              .children(
                blockRuns.map((runs) =>
                  h_flex()
                    .h(rowHeight())
                    .items_center()
                    .whitespace_nowrap()
                    .children(
                      runs.map((run) =>
                        div()
                          .flex_none()
                          .whitespace_nowrap()
                          .text_color(SYNTAX[run.kind] ?? t.foreground)
                          .child(run.text || " "),
                      ),
                    ),
                ),
              ),
          ),
      );
  },

  previewView() {
    // `#anchor` links scroll to their heading's block, a direct child of this list.
    return v_flex()
      .id("viewer-preview")
      .flex_1()
      .min_h(0)
      .min_w(0)
      .overflow_y_scrollbar()
      .when(Boolean(this.previewScroll), (el) => el.track_scroll(this.previewScroll))
      .px(24)
      .py(16)
      .gap(12)
      .children(
        this.previewBlocks().map((block, i) => {
          if (block.type === "image") return this.previewImage(block, `viewer-image-${i}`);
          if (block.type === "images") return this.previewImages(block, i);
          if (block.type === "code") return this.previewCode(block, i);

          const id = `viewer-md-${this.viewerId}-${i}`;
          const markdown = (key, text) => Markdown(key, text).on_link_click((url, cx) => this.followLink(url, cx));
          // shortcut: style leading ATX headings; use native heading styles when TextView exposes them.
          const heading = /^( {0,3}(#{1,6})(?:[ \t]+[^\n]*|(?=\n|$)))(?:\n|$)/.exec(block.text);
          const section = i > 0 && Boolean(heading);
          if (!heading || heading[2].length > 2) return markdown(id, block.text).when(section, (el) => el.mt(12));

          const body = block.text.slice(heading[0].length);
          const lines = body.split("\n").filter((line) => line.trim());
          const references = lines.filter((line) => REFERENCE.test(line));
          return v_flex()
            .when(section, (el) => el.mt(12))
            .gap(10)
            .child(
              div().border_b_1().border_color(theme().border).pb(5)
                .child(markdown(id, [heading[1], "", ...references].join("\n"))),
            )
            .when(lines.length > references.length, (el) => el.child(markdown(`${id}-body`, body)));
        }),
      );
  },

  viewerActions() {
    const file = this.file;
    const preview = this.viewerEntry()?.preview;
    const editors = file?.on ? [] : foundEditors();
    const markdown = Boolean(file && isMarkdown(file.path));
    const previewing = this.showsPreview();
    const showView = (view) => (cx) => {
      this.setViewer(this.viewerId, { markdown: view });
      cx.notify();
    };
    // Only changes that replaced something have old lines to show.
    const openable = this.gutterOn && !previewing ? (this.hunks ?? []).filter((hunk) => hunk.old.length).map(hunkKey) : [];
    const allOpen = openable.length > 0 && openable.every((key) => this.openHunks.has(key));
    return h_flex()
      .id("viewer-actions")
      .gap(6)
      .items_center()
      .when(markdown, (el) =>
        el.child(
          h_flex()
            .id("viewer-view")
            .gap(2)
            .child(TextButton({ id: "viewer-view-preview", label: "Preview", active: previewing, onClick: showView("preview") }))
            .child(TextButton({ id: "viewer-view-code", label: "Code", active: !previewing, onClick: showView("code") })),
        ),
      )
      .when(openable.length > 0, (el) =>
        el.child(
          TextButton({
            id: "viewer-show-old",
            label: "Expand all",
            active: allOpen,
            onClick: (cx) => {
              this.openHunks = new Set(allOpen ? [] : openable);
              cx.notify();
            },
          }),
        ),
      )
      .when(Boolean(preview), (el) =>
        el.child(
          TextButton({
            id: "viewer-keep",
            label: "Keep tab",
            onClick: (cx) => {
              this.setViewer(this.viewerId, { preview: false });
              cx.notify();
            },
          }),
        ),
      )
      .when(editors.length > 0, (el) =>
        el.child(
          this.chooser({
            id: "viewer-open-in",
            accessibilityLabel: "Open in an editor",
            width: 200,
            trigger: MenuButton({ id: "viewer-open-in-trigger", label: "Open in" }),
            choices: editors.map((e) => ({ id: editorId(e), label: e.name })),
            onChoose: (id) => {
              this.openInEditor(editors.find((e) => editorId(e) === id), file.path);
            },
          }),
        ),
      );
  },

  viewerView() {
    const t = theme();
    const head = this.viewerHead();
    const inHeader = this.headerShowsTitle();
    const root = v_flex()
      .id("better-files-viewer")
      .relative()
      .size_full()
      .min_w(0)
      .min_h(0)
      .overflow_hidden()
      .bg(t.background)
      .text_color(t.foreground)
      .text_size(TEXT.body);
    if (!inHeader && head)
      root.child(
        h_flex()
          .id("viewer-bar")
          .h(30)
          .flex_none()
          .px(10)
          .gap(8)
          .items_center()
          .border_b(1)
          .border_color(t.border)
          .text_size(TEXT.small)
          .child(
            FileIcon({ icons: this.fileIcons, path: this.file.path, color: t.dim, t }),
          )
          .child(div().flex_none().truncate().max_w(260).font_medium().child(head.title))
          .child(div().flex_1().min_w(0).truncate().text_color(t.dim).child(head.detail))
          .child(this.viewerActions()),
      );
    if (this.file && isImage(this.file.path)) root.child(this.imageView());
    else if (this.problem) root.child(Message(this.problem));
    else if (this.text === undefined) root.child(Message(head ? "Loading…" : "This tab has no file."));
    else if (this.showsPreview()) root.child(this.previewView());
    else if (this.gutterOn) root.child(this.linesView());
    else root.child(v_flex().flex_1().min_h(0).child(Editor.new(this.code).flex_1().min_h(0)));
    // There's no row of its own to sit in, so the actions float over the file's corner.
    // On the file's own colour, nearly opaque, so the text under it fades out without a box.
    if (inHeader)
      root.child(
        div()
          .absolute()
          .top(6)
          .right(18)
          .p(3)
          .rounded(7)
          .bg(`${t.background.slice(0, 7)}E6`)
          .child(this.viewerActions()),
      );
    return root;
  },
};
