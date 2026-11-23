// The diff: opening a file in the centre tab, reading it, and drawing it.
import { div } from "gpui-kit";
import { h_flex, Scrollbar, v_virtual_list } from "gpui-base";
import { spaces, panes, readTextFile, theme, shared, setShared, run, layout } from "herdr";
import { diffRows, splitDiffRows, conflictRows } from "../git/model.js";
import { WHOLE_FILE_LINES, languageOf, syntaxColors, tokenizeLine } from "../syntax.js";
import { TEXT, SIZE, codeFont, codeSize, FileIcon, Panel, PaneBar, DiffStat, Message, TextButton } from "./ui.js";
import { fileIcon, isLight } from "../file-icons.js";

const TAB_OPEN_TIMEOUT_MS = 1500;
const NO_PATCH = "No text diff: GitHub leaves out binary and very large files.";
// In widths of the code font's size, so a diff looks the same at any terminal size.
const CHAR_WIDTH = 0.62;
const GUTTERS = 10;
const rowHeight = () => Math.round(codeSize() * 1.5);
const scrollWidth = (lengths) =>
  Math.max(300, ...lengths.map((length) => (length * CHAR_WIDTH + GUTTERS) * codeSize()));

export const diffMethods = {
  // A reopened tab shows the file it last showed. Never replaces a live entry,
  // which may hold a newer pick.
  restoreDiffSelection(p) {
    if (this.mode !== "diff" || !this.diffSpace) return;
    const entries = shared("better-changes.diff-tabs") ?? {};
    if (entries[this.diffSpace]) return;
    let selection = p.selection;
    let source = p.source;
    try {
      const saved = JSON.parse(localStorage.getItem("diff.selection"));
      if (typeof saved?.path === "string" && typeof JSON.parse(saved.context)?.cwd === "string") {
        selection = saved;
        source = JSON.parse(saved.context);
      }
    } catch {
      // Missing or malformed saved state is harmless: the props still say what to show.
    }
    setShared("better-changes.diff-tabs", { ...entries, [this.diffSpace]: { source, selection } });
  },

  // ── Opening a file in the centre ──────────────────────────────────────────

  diffTab(space = this.diffSpace) {
    const ids = new Set((spaces().find((s) => s.id === space)?.tabs ?? []).map((t) => t.id));
    return panes().find((p) => p.mod === "better-changes" && ids.has(p.tab))?.tab;
  },

  pick(file, scope, cx) {
    const space = spaces().find((s) => s.active);
    if (!space) return;
    const selected = {
      context: this.context,
      root: this.root,
      on: this.on,
      path: file.path,
      scope,
      at: Date.now(),
    };
    if (scope === "commit") {
      const { hash, short, subject } = this.selectedCommit;
      selected.commit = { hash, short, subject };
      selected.file = file;
    }
    if (scope === "committed") {
      selected.commit = { base: this.committed.base, name: this.committed.name };
      selected.file = file;
    }
    const entries = shared("better-changes.diff-tabs") ?? {};
    const old = entries[space.id];
    const tab = this.diffTab(space.id);
    const source = JSON.parse(this.context);
    const name = file.path.split("/").pop();
    // Published before the tab opens so its copy sees the latest pick. The
    // pending time keeps rapid clicks from opening two tabs.
    setShared("better-changes.selection", selected);
    setShared("better-changes.diff-tabs", {
      ...entries,
      [space.id]: {
        source,
        selection: selected,
        pending: tab ? null : (old?.pending ?? Date.now()),
      },
    });
    if (tab) {
      run("tab.rename", { id: tab, name });
      run("tab.select", { id: tab });
    } else if (!old?.pending || Date.now() - old.pending > TAB_OPEN_TIMEOUT_MS) {
      run("tab.new", {
        space: space.id,
        name,
        mod: "better-changes",
        props: { mode: "diff", space: space.id, source, selection: selected },
      });
    }
    cx.notify();
  },

  syncSelection(cx) {
    const entry = (shared("better-changes.diff-tabs") ?? {})[this.diffSpace];
    const selected = entry?.selection;
    if (!selected || selected.context !== this.context) return;
    const id = JSON.stringify(selected);
    if (id === this.selection) return;
    const tab = this.diffTab();
    if (tab && entry.pending)
      setShared("better-changes.diff-tabs", {
        ...shared("better-changes.diff-tabs"),
        [this.diffSpace]: { ...entry, pending: null },
      });
    localStorage.setItem("diff.selection", JSON.stringify(selected));
    this.selection = id;
    this.freshLines = null;
    this.conflictCount = 0;
    this.path = selected.path;
    this.scope = selected.scope;
    this.commitRef = selected.commit ?? null;
    this.commitFile = selected.file ?? null;
    this.splitOffset = 0;
    this.rows = [];
    this.note = null;
    this.diffToken++;
    this.diffLoading = false;
    if (this.root) this.loadDiff(cx);
    cx.notify();
  },

  diffFile() {
    if (["commit", "committed", "patch"].includes(this.scope)) return this.commitFile;
    const file = this.files.find((f) => f.path === this.path);
    if (!file) return null;
    // Git's counts for a conflict are of the markers, so they would mislead.
    if (file.conflict) return { ...file, add: 0, del: 0 };
    const stats = this.scope === "staged" ? file.stagedStats : file.unstagedStats;
    // Git counts nothing for an untracked file, so its lines come from reading it.
    return {
      ...file,
      ...stats,
      ...(file.fresh && this.freshLines ? { add: this.freshLines } : {}),
    };
  },

  // Whether diffs show the whole file around their changes. The header row toggles it for every diff tab.
  fullFile() {
    return shared("better-changes.full-file") ?? localStorage.getItem("full-file") === "1";
  },

  toggleFullFile() {
    const full = !this.fullFile();
    localStorage.setItem("full-file", full ? "1" : "0");
    setShared("better-changes.full-file", full);
  },

  FullFileButton() {
    return TextButton({
      id: "diff-full-file",
      label: "Full file",
      active: this.fullFile(),
      onClick: (cx) => {
        this.toggleFullFile();
        cx.notify();
      },
    });
  },

  diffArgs() {
    if (this.scope === "commit")
      return ["show", "--diff-merges=first-parent", "--format=", this.commitRef.hash];
    if (this.scope === "committed") return ["diff", this.commitRef.base, "HEAD"];
    return ["diff", ...(this.scope === "staged" ? ["--cached"] : [])];
  },

  // What to show for a conflicted file: its marked blocks, or a sentence when
  // there are none, as when one side deleted the file.
  async readConflict(path, root, on) {
    const stages = await this.git(["ls-files", "-u", "-z", "--", path], root, on);
    if (stages.code !== 0) throw Error(stages.stderr || "Cannot read the conflict");
    const present = new Set(
      stages.stdout
        .split("\0")
        .filter(Boolean)
        .map((entry) => entry.split(/\s+/)[2]),
    );
    if (!present.has("2"))
      return { message: "Conflict: deleted on your side, changed on the incoming side." };
    if (!present.has("3"))
      return { message: "Conflict: changed on your side, deleted on the incoming side." };
    const text = await readTextFile(`${root}/${path}`, { on });
    if (text === null)
      return { message: "Conflict: cannot read this file. It may be binary or too large." };
    if (text.includes("\0")) return { message: "Conflict: binary file, no text diff." };
    const rows = conflictRows(text);
    return rows
      ? { rows }
      : { message: "No conflict markers left. Stage the file to mark it resolved." };
  },

  showRows(rows, paired) {
    this.truncated = false;
    this.rows = rows;
    this.pairedRows = paired;
    const lengths = rows.map((row) => row.text.length);
    this.width = scrollWidth(lengths);
  },

  loadDiff(cx) {
    this.shownFull = this.fullFile();
    const { path, context, root, on, scope } = this;
    const file = this.diffFile();
    const token = ++this.diffToken;
    this.note = null;
    if (!file || (scope === "staged" && !file.staged) || (scope === "unstaged" && !file.unstaged)) {
      this.rows = [];
      this.note = "This file has no changes left here.";
      this.diffLoading = false;
      cx.notify();
      return;
    }

    const isStale = () => token !== this.diffToken || !this.isCurrent(context);
    this.diffLoading = true;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const content = await this.readDiffContent(file, path, root, on);
        if (isStale()) return;
        this.freshLines = content.freshLines ?? null;
        this.conflictCount = content.conflict?.count ?? 0;
        if (content.conflict) this.showRows(content.conflict.inline, content.conflict.split);
        else this.showLines(content.lines);
      } catch (error) {
        if (token === this.diffToken) {
          this.rows = [];
          this.note = error.message;
        }
      } finally {
        if (token === this.diffToken) {
          this.diffLoading = false;
          cx.notify();
        }
      }
    });
  },

  async readDiffContent(file, path, root, on) {
    // A diff handed over whole, as Branch PR does with GitHub's patch for a PR's file.
    // shortcut: Full file has no effect here, GitHub's patch has only its hunks.
    if (this.scope === "patch")
      return { lines: file.patch?.split("\n") ?? [NO_PATCH] };
    if (file.fresh) return this.readFreshFile(path, root, on);
    if (file.conflict) {
      const { rows, message } = await this.readConflict(path, root, on);
      return rows ? { conflict: rows } : { lines: [message] };
    }
    return { lines: await this.readDiffLines(file, path, root, on) };
  },

  // An untracked file has nothing to diff against, so every line is an addition.
  async readFreshFile(path, root, on) {
    const text = await readTextFile(`${root}/${path}`, { on });
    if (text === null)
      return { lines: ["Cannot preview this file: binary, too large, or unreadable."] };
    if (text.includes("\0")) return { lines: ["Binary file · no text diff"] };
    if (!text) return { lines: ["Empty new file"] };
    const all = text.replace(/\n$/, "").split("\n");
    return {
      freshLines: all.length,
      lines: [`@@ -0,0 +1,${all.length} @@`, ...all.map((line) => `+${line}`)],
    };
  },

  async readDiffLines(file, path, root, on) {
    const args = ["--literal-pathspecs", ...this.diffArgs()];
    // shortcut: a file over 1,000,000 lines still shows in pieces, fine for a diff view.
    if (this.shownFull) args.push("--unified=1000000");
    args.push("--no-ext-diff", "--no-textconv", "--no-color", "--", path);
    const result = await this.git(args, root, on);
    if (result.code !== 0) throw Error(result.stderr || "Cannot read diff");
    const all = result.stdout.replace(/\n$/, "").split("\n");
    const first = all.findIndex((line) => line.startsWith("@@"));
    if (first >= 0) return all.slice(first);
    return [file.binary ? "Binary file changed" : "No text diff (mode or submodule change)"];
  },

  showLines(lines) {
    const { diff_lines: maxLines, line_length: maxLength } = this.settings.limits;
    this.truncated = lines.length > maxLines || lines.some((line) => line.length > maxLength);
    const visible = lines
      .slice(0, maxLines)
      .map((line) => (line.length > maxLength ? `${line.slice(0, maxLength)}…` : line));
    this.rows = diffRows(visible);
    this.pairedRows = splitDiffRows(this.rows);
    this.width = scrollWidth(visible.map((line) => line.length));
  },

  conflictLabel() {
    const count = this.conflictCount;
    return count ? `${count} ${count === 1 ? "conflict" : "conflicts"}` : "Conflict";
  },

  // What this diff is, for the row above it.
  head() {
    const file = this.diffFile();
    const parts = (this.path ?? "").split("/");
    const title = parts.pop() || "No file";
    const scopes = {
      staged: "Staged",
      unstaged: "Unstaged",
      committed: "Committed",
      commit: this.commitRef?.short,
      patch: this.commitRef?.short,
    };
    const scope = file?.conflict ? this.conflictLabel() : scopes[this.scope];
    const picture = this.path && fileIcon(this.fileIcons, `${this.root}/${this.path}`, { light: isLight(theme().background) });
    return {
      title,
      detail: [parts.join("/"), scope].filter(Boolean).join(" · "),
      // color: a full-colour picture, which the pane header draws untinted.
      ...(picture ? { icon: picture, color: true } : { icon: "mods/better-changes/icons/file.svg" }),
      add: file?.add ?? 0,
      del: file?.del ?? 0,
    };
  },

  // Shown in the pane's own header when the layout uses ours, so there's one row.
  publishHead() {
    const pane = panes().find((p) => p.mod === "better-changes" && p.tab === this.diffTab())?.pane;
    if (!pane) return;
    const head = this.head();
    const heads = shared("pane-heads") ?? {};
    if (JSON.stringify(heads[pane]) !== JSON.stringify(head))
      setShared("pane-heads", { ...heads, [pane]: head });
  },

  layoutUsesOurHeader() {
    const find = (node) =>
      node?.content?.pane?.header?.content?.mod ?? (node?.children ?? []).map(find).find(Boolean);
    return find(layout()) === "better-changes";
  },

  renderDiff() {
    const root = Panel({ id: "better-changes-diff", framed: false });
    const split = this.diffLayout === "split";
    if (!this.layoutUsesOurHeader()) root.child(this.renderFileRow());
    if (this.error || this.note) root.child(Message(this.error || this.note, true));
    if (this.diffLoading && !this.rows.length) root.child(Message("Loading diff…"));
    if (split) root.child(this.renderColumnTitles());
    root.child(this.renderDiffRows(split));
    if (this.truncated) {
      const limit = this.settings.limits.diff_lines.toLocaleString();
      root.child(Message(`Showing the first ${limit} lines.`));
    }
    return root;
  },

  // For a layout that uses Herdr's own pane header.
  renderFileRow() {
    const t = theme();
    const head = this.head();
    return PaneBar()
      .child(FileIcon({ icons: this.path && this.fileIcons, path: `${this.root}/${this.path}`, color: t.dim, t }))
      .child(div().flex_none().truncate().max_w(260).font_medium().child(head.title))
      .child(div().flex_1().min_w(0).truncate().text_color(t.dim).child(head.detail))
      .child(DiffStat(head))
      .child(this.FullFileButton());
  },

  renderColumnTitles() {
    const t = theme();
    const conflict = Boolean(this.diffFile()?.conflict);
    return h_flex()
      .h(SIZE.row)
      .flex_none()
      .items_center()
      .border_b(1)
      .border_color(t.border)
      .text_size(TEXT.caption)
      .text_color(t.muted)
      .child(
        div()
          .flex_1()
          .px(12)
          .child(conflict ? "Yours" : "Before"),
      )
      .child(
        div()
          .flex_1()
          .h_full()
          .flex()
          .items_center()
          .px(12)
          .border_l(1)
          .border_color(t.border)
          .child(conflict ? "Incoming" : "After"),
      );
  },

  renderDiffRows(split) {
    const rows = split ? (this.pairedRows ?? []) : this.rows;
    const listId = `diff-${this.context}-${this.path}-${this.scope}-${this.diffLayout}`;
    const list = v_virtual_list(
      listId,
      rows.length,
      rowHeight(),
      (i) => String(i),
      (range) =>
        rows
          .slice(range.start, range.end)
          .map((row) => (split ? this.splitRow(row) : this.inlineRow(row))),
    ).size_full();
    return div()
      .flex_1()
      .min_h(0)
      .relative()
      .font_family(codeFont())
      .text_size(codeSize())
      .child(split ? this.scrollsTogether(list) : this.scrollsSideways(list))
      .child(Scrollbar.vertical(listId).viewport_from_layout().absolute().inset_0());
  },

  // Side by side moves both columns with one offset, keeping the line numbers still.
  scrollsTogether(list) {
    return list.on_scroll_wheel((e, cx) => {
      const delta = e.delta.x || (e.modifiers?.shift ? e.delta.y : 0);
      if (!delta) return;
      const furthest = Math.max(0, (this.width || 300) - 160);
      this.splitOffset = Math.max(0, Math.min(furthest, this.splitOffset - delta));
      cx.stop_propagation();
      cx.notify();
    });
  },

  scrollsSideways(list) {
    return div()
      .id("diff-x")
      .size_full()
      .overflow_x_scrollbar()
      .child(
        div()
          .w_full()
          .min_w(this.width || 300)
          .h_full()
          .child(list),
      );
  },

  // The text colour and background of a row, by what kind of line it is.
  rowLook(kind) {
    const t = theme();
    const tinted = (color) => ({ color, background: `${color}26` });
    if (kind === "+" || kind === "incoming") return tinted(t.ansi2);
    if (kind === "-") return tinted(t.ansi1);
    if (kind === "yours") return tinted(t.accent);
    if (kind === "base") return { color: t.dim, background: null };
    if (kind === "marker") return { color: t.foreground, background: t.raised };
    return { color: t.foreground, background: null };
  },

  inlineRow(row) {
    const t = theme();
    if (row.kind === "@")
      return div().h(rowHeight()).px(12).w_full().bg(t.raised).text_color(t.accent).child(row.text);
    const { color, background } = this.rowLook(row.kind);
    const gutter = (value) =>
      div()
        .w(codeSize() * 3.5)
        .flex_none()
        .text_right()
        .text_color(t.dim)
        .child(value === undefined ? "" : String(value));
    const sign = row.kind === "+" || row.kind === "-" ? row.kind : "";
    return h_flex()
      .h(rowHeight())
      .w_full()
      .gap(8)
      .items_center()
      .when(Boolean(background), (el) => el.bg(background))
      .when(!this.conflictCount, (el) => el.child(gutter(row.old)))
      .child(gutter(row.next))
      .child(div().w(codeSize()).flex_none().text_color(color).child(sign))
      .child(div().flex_1().min_w(0).whitespace_nowrap().child(this.codeText(row, color)));
  },

  // Worked out once per diff, since rows are drawn on every scroll. The old and new sides
  // each carry their own open comment or string, and a hunk header starts both afresh. A
  // huge diff, or one the lexer fails on, is left to `runsOf`, a row at a time.
  highlightRows() {
    const language = languageOf(this.path);
    const runs = new Map();
    let before = null;
    let after = null;
    try {
      if (this.rows.length <= WHOLE_FILE_LINES)
        for (const row of this.rows) {
          if (row.kind === "@" || row.kind === "marker") {
            before = after = null;
            continue;
          }
          if (!["+", "-", " ", "yours", "incoming"].includes(row.kind)) continue;
          const result = tokenizeLine(row.text ?? "", language, row.kind === "-" ? before : after);
          runs.set(row, result.runs);
          if (row.kind === "-") before = result.state;
          else if (row.kind === " ") before = after = result.state;
          else after = result.state;
        }
    } catch {
      runs.clear();
    }
    this.syntaxFor = this.rows;
    this.syntaxRuns = runs;
  },

  // A conflict's side-by-side rows are copies, so they miss the map and start fresh.
  runsOf(row) {
    if (["@", "marker", "base", ""].includes(row.kind)) return null;
    if (this.syntaxFor !== this.rows) this.highlightRows();
    const runs = this.syntaxRuns.get(row);
    if (runs) return runs;
    try {
      return tokenizeLine(row.text ?? "", languageOf(this.path)).runs;
    } catch {
      return [{ text: row.text ?? "", kind: null }];
    }
  },

  // Text that isn't a token takes the theme's own colour on a change: the background and
  // the sign already say it was added or removed.
  codeText(row, color) {
    const runs = row ? this.runsOf(row) : null;
    if (!runs) return div().text_color(color).child(row?.text || " ");
    const t = theme();
    const colors = syntaxColors(t);
    return h_flex().children(
      runs.map((run) =>
        div()
          .flex_none()
          .whitespace_nowrap()
          .text_color(colors[run.kind] ?? t.foreground)
          .child(run.text || " "),
      ),
    );
  },

  splitRow(row) {
    const t = theme();
    if (row.kind !== "pair")
      return div()
        .h(rowHeight())
        .px(12)
        .w_full()
        .bg(t.raised)
        .text_color(row.kind === "@" ? t.accent : t.dim)
        .truncate()
        .child(row.text);
    const side = (entry, line, right) => {
      const { color, background } = this.rowLook(entry?.kind);
      const sign = entry?.kind === "+" || entry?.kind === "-" ? entry.kind : "";
      return h_flex()
        .flex_1()
        .min_w(0)
        .h_full()
        .gap(6)
        .items_center()
        .overflow_hidden()
        .when(right, (el) => el.border_l(1).border_color(t.border))
        .when(Boolean(background), (el) => el.bg(background))
        .when(!entry, (el) => el.bg(t.raised))
        .child(
          div()
            .w(codeSize() * 3.5)
            .flex_none()
            .text_right()
            .text_color(t.dim)
            .child(entry ? String(line ?? "") : ""),
        )
        .child(div().w(codeSize()).flex_none().text_color(color).child(sign))
        .child(
          div()
            .flex_1()
            .min_w(0)
            .overflow_hidden()
            .child(
              div()
                .w(this.width || 300)
                .flex_none()
                .ml(-this.splitOffset)
                .whitespace_nowrap()
                .child(this.codeText(entry, color)),
            ),
        );
    };
    return h_flex()
      .h(rowHeight())
      .w_full()
      .child(side(row.left, row.left?.old, false))
      .child(side(row.right, row.right?.next, true));
  },
};
