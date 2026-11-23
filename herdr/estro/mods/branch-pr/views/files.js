// The Files tab: what the PR changes, file by file. A click shows that file's diff
// in Better Changes' centre tab when that mod is installed, otherwise on GitHub.
import { div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, theme, shared, setShared, run } from "herdr";
import { fileTree } from "../github/model.js";
import { TEXT, codeFont, Chevron, FileIcon, IconButton, Message, Row } from "./ui.js";

const TAB_OPEN_TIMEOUT_MS = 1500;
// A row's left padding, 8 as in Row, then a step per folder above it.
const indent = (depth) => 8 + depth * 14;

export const filesMethods = {
  // Read once per head commit, so a refresh with no new push costs nothing.
  loadFiles(cx) {
    const pr = this.pr;
    if (!pr) return;
    const key = `${pr.repository}#${pr.number}@${pr.headRefOid}`;
    if (this.prFiles?.key === key && !this.prFiles.error) return;
    this.prFiles = { key, loading: true };
    cx.spawn(async (cx) => {
      let next;
      try {
        const pages = await this.api({ action: "files", repo: pr.repository, number: pr.number });
        next = { key, list: pages.flat() };
      } catch (e) {
        next = { key, error: e.message };
      }
      if (this.prFiles?.key === key) this.prFiles = next;
      cx.notify();
    });
  },

  filesView(body) {
    const t = theme();
    const files = this.prFiles;
    if (!files || files.loading) return body.child(Message("Loading files…"));
    if (files.error) return body.child(Message(files.error, true));
    if (!files.list.length) return body.child(Message("No files changed."));
    const tree = this.fileLayout === "tree";
    body.child(
      h_flex()
        .pl(8)
        .pb(4)
        .items_center()
        .child(
          div()
            .flex_1()
            .text_size(TEXT.caption)
            .text_color(t.dim)
            .child(`${files.list.length} ${files.list.length === 1 ? "file" : "files"}`),
        )
        .child(
          IconButton({
            id: "pr-files-layout",
            icon: tree ? "flat" : "tree",
            label: tree ? "Show as list" : "Show as tree",
            small: true,
            onClick: (cx) => {
              this.fileLayout = tree ? "flat" : "tree";
              localStorage.setItem("files-layout", this.fileLayout);
              cx.notify();
            },
          }),
        ),
    );
    if (!tree) {
      for (const file of files.list) body.child(this.fileRow(file, 0, true));
      return;
    }
    for (const row of fileTree(files.list, this.closedFolders))
      body.child(row.kind === "folder" ? this.folderRow(row) : this.fileRow(row.file, row.depth));
  },

  folderRow(row) {
    const t = theme();
    const closed = this.closedFolders.has(row.path);
    return Row({
      id: `pr-folder-${row.path}`,
      onClick: (cx) => {
        if (closed) this.closedFolders.delete(row.path);
        else this.closedFolders.add(row.path);
        cx.notify();
      },
    })
      .pl(indent(row.depth))
      .child(Chevron(!closed))
      .when(Boolean(this.fileIcons), (el) =>
        el.child(FileIcon({ icons: this.fileIcons, path: row.path, dir: true, open: !closed, t })),
      )
      .child(div().flex_1().min_w(0).truncate().child(row.name));
  },

  // In a flat list the folder follows the name, dim.
  fileRow(file, depth, flat = false) {
    const t = theme();
    const parts = file.filename.split("/");
    const name = parts.pop();
    const stat = (text, color) =>
      div()
        .flex_none()
        .font_family(codeFont())
        .text_size(TEXT.caption)
        .text_color(color)
        .child(text);
    return Row({ id: `pr-file-${file.filename}`, onClick: (cx) => this.openFile(file, cx) })
      .pl(indent(depth))
      .when(this.openFilePath === file.filename, (el) => el.bg(t.selected))
      .tooltip(file.filename)
      .child(FileIcon({ icons: this.fileIcons, path: file.filename, color: t.muted, t }))
      .child(
        div()
          .min_w(0)
          .when(!flat, (el) => el.flex_1())
          .truncate()
          .child(name),
      )
      .when(flat, (el) =>
        el.child(
          div()
            .flex_1()
            .min_w(0)
            .truncate()
            .text_size(TEXT.caption)
            .text_color(t.dim)
            .child(parts.join("/")),
        ),
      )
      .child(stat(`+${file.additions}`, t.ansi2))
      .child(stat(`−${file.deletions}`, t.ansi1));
  },

  // Hands GitHub's patch to Better Changes the way its own sidebar picks a file:
  // the selection goes in shared state first, then its diff tab opens or is selected.
  // shortcut: depends on Better Changes' shared("better-changes.diff-tabs") shape; change both together.
  openFile(file, cx) {
    const pr = this.pr;
    this.openFilePath = file.filename;
    const space = spaces().find((s) => s.active);
    if (!this.hasBetterChanges || !space || !this.sp?.folder) {
      // shortcut: opens the PR's Files page, not the file's anchor (a SHA-256 of its path).
      cx.open_url(`${pr.url}/files`);
      return cx.notify();
    }
    const source = { cwd: this.sp.folder, on: this.sp.machine ?? null };
    const selection = {
      context: JSON.stringify(source),
      path: file.filename,
      scope: "patch",
      commit: { short: `PR #${pr.number}` },
      file: {
        path: file.filename,
        add: file.additions,
        del: file.deletions,
        patch: file.patch ?? null,
      },
      at: Date.now(),
    };
    const ids = new Set((space.tabs ?? []).map((t) => t.id));
    const tab = panes().find((p) => p.mod === "better-changes" && ids.has(p.tab))?.tab;
    const entries = shared("better-changes.diff-tabs") ?? {};
    const old = entries[space.id];
    const name = file.filename.split("/").pop();
    // The pending time keeps rapid clicks from opening two tabs, as in Better Changes.
    setShared("better-changes.diff-tabs", {
      ...entries,
      [space.id]: { source, selection, pending: tab ? null : (old?.pending ?? Date.now()) },
    });
    if (tab) {
      run("tab.rename", { id: tab, name });
      run("tab.select", { id: tab });
    } else if (!old?.pending || Date.now() - old.pending > TAB_OPEN_TIMEOUT_MS) {
      run("tab.new", {
        space: space.id,
        name,
        mod: "better-changes",
        props: { mode: "diff", space: space.id, source, selection },
      });
    }
    cx.notify();
  },
};
