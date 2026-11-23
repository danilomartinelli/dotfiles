// The sidebar: its tabs, options menu, file groups and commit views.
import { div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { theme, shared, setShared } from "herdr";
import { fileTree, timeAgo } from "../git/model.js";
import {
  TEXT,
  SPIN_MS,
  codeFont,
  FileIcon,
  Chevron,
  Panel,
  PanelHeader,
  HeaderTab,
  IconButton,
  TextButton,
  GroupHeader,
  Row,
  DiffStat,
  StatusLetter,
  Message,
  Menu,
  MenuLabel,
  MenuDivider,
  MenuOption,
  TextBox,
  SplitButton,
  SplitTrigger,
} from "./ui.js";

const VIEWS = [
  { id: "flat", label: "Flat", icon: "flat" },
  { id: "tree", label: "Tree", icon: "tree" },
];
const LAYOUTS = [
  { id: "inline", label: "Inline", icon: "diff-inline" },
  { id: "split", label: "Side by side", icon: "diff-split" },
];

export const sidebarMethods = {
  // ── Preferences ───────────────────────────────────────────────────────────

  setTab(tab, cx) {
    this.tab = tab;
    localStorage.setItem("tab", tab);
    if (tab === "commit") this.loadCommits(cx);
    cx.notify();
  },

  setView(view, cx) {
    this.view = view;
    localStorage.setItem("view", view);
    cx.notify();
  },

  toggleGroup(scope, cx) {
    if (!this.collapsed.delete(scope)) this.collapsed.add(scope);
    localStorage.setItem("collapsed", JSON.stringify([...this.collapsed]));
    cx.notify();
  },

  setDiffLayout(style, cx) {
    this.diffLayout = style;
    localStorage.setItem("diff-layout", style);
    setShared("better-changes.diff-layout", style);
    cx.notify();
  },

  // ── Sidebar ───────────────────────────────────────────────────────────────

  render() {
    if (this.mode === "panel-key") return div();
    if (this.mode === "pane-header") return this.renderPaneHeader();
    if (this.mode === "diff") return this.renderDiff();
    return Panel({ id: "better-changes" })
      .child(this.renderHeader())
      .child(
        this.tab === "commit"
          ? this.selectedCommit
            ? this.renderCommit()
            : this.renderHistory()
          : this.renderChanges(),
      );
  },

  renderHeader() {
    const unpushed = this.committed?.unpushed.size;
    return PanelHeader()
      .child(
        h_flex()
          .flex_1()
          .min_w(0)
          .ml(-8) // Lines the pills up with the list rows below.
          .gap(4)
          .items_center()
          .role("tab_list")
          .child(
            HeaderTab({
              id: "tab-changes",
              label: "Changes",
              count: this.total || null,
              active: this.tab === "changes",
              onClick: (cx) => this.setTab("changes", cx),
            }),
          )
          .child(
            HeaderTab({
              id: "tab-commit",
              label: "Commits",
              count: unpushed,
              active: this.tab === "commit",
              onClick: (cx) => this.setTab("commit", cx),
            }),
          ),
      )
      .child(
        IconButton({
          id: "refresh",
          icon: "refresh",
          label: "Refresh",
          spinning: this.refreshSpinning,
          onClick: (cx) => this.refreshAll(cx),
        }),
      )
      .child(this.renderMore());
  },

  refreshAll(cx) {
    this.refresh(cx);
    if (this.tab === "commit") this.loadCommits(cx);
    if (this.refreshSpinning) return;
    this.refreshSpinning = true;
    cx.notify();
    cx.timer.after(SPIN_MS, (cx) => this.stopSpinningWhenRead(cx));
  },

  // Git usually answers at once, so the icon always makes a full turn to be seen.
  stopSpinningWhenRead(cx) {
    if (this.loading || this.commitsLoading) {
      cx.timer.after(SPIN_MS, (cx) => this.stopSpinningWhenRead(cx));
      return;
    }
    this.refreshSpinning = false;
    cx.notify();
  },

  renderMore() {
    const option = (group, choice, selected, set) =>
      MenuOption({
        id: `${group}-${choice.id}`,
        icon: choice.icon,
        label: choice.label,
        selected,
        onClick: (cx) => {
          this.menuOpen = false;
          set(choice.id, cx);
          cx.notify();
        },
      });
    return Menu({
      id: "more",
      open: this.menuOpen,
      focus: this.menuFocus,
      onOpenChange: (open, cx) => {
        this.menuOpen = open;
        cx.notify();
      },
      trigger: IconButton({ id: "more-trigger", icon: "more", label: "Options" }),
      children: [
        MenuLabel("Changes"),
        ...VIEWS.map((v) =>
          option("view", v, this.view === v.id, (id, cx) => this.setView(id, cx)),
        ),
        MenuDivider(),
        MenuLabel("Diff"),
        ...LAYOUTS.map((l) =>
          option("layout", l, this.diffLayout === l.id, (id, cx) => this.setDiffLayout(id, cx)),
        ),
      ],
    });
  },

  renderChanges() {
    const list = v_flex().id("changes-list").flex_1().min_h(0).overflow_y_scrollbar().p(6);
    if (this.error) return list.child(Message(this.error, true));
    const conflicts = this.files.filter((f) => f.conflict);
    const unstaged = this.files.filter((f) => f.unstaged && !f.conflict);
    const staged = this.files.filter((f) => f.staged);
    const committed = this.committed?.total ? this.committed : null;
    if (!conflicts.length && !unstaged.length && !staged.length && !committed)
      list.child(Message(this.loading || !this.root ? "Loading changes…" : "No changes"));
    this.groupsDrawn = 0;
    this.addGroup(list, "conflict", "Conflicts", conflicts);
    this.addGroup(list, "staged", "Staged", staged);
    this.addGroup(list, "unstaged", "Unstaged", unstaged);
    if (committed)
      this.addGroup(
        list,
        "committed",
        "Committed",
        committed.files,
        `not on ${committed.name}`,
        committed.total,
      );
    const limit = this.settings.limits.files;
    if (this.total > limit)
      list.child(Message(`Showing the first ${limit.toLocaleString()} changed files.`));
    return v_flex().id("changes").flex_1().min_h(0).child(list).child(this.renderCommitBox());
  },

  renderCommitBox() {
    const t = theme();
    const hint = this.commitBoxHint();
    return v_flex()
      .id("commit-box")
      .flex_none()
      .p(10)
      .gap(8)
      .border_t(1)
      .border_color(t.border)
      .when(Boolean(this.note), (el) =>
        el.child(
          div()
            .text_size(TEXT.small)
            .text_color(t.ansi1)
            .whitespace_normal()
            .child(this.note ?? ""),
        ),
      )
      .child(
        TextBox({
          id: "commit-message",
          state: this.input,
          focused: this.typing,
          label: "Commit message",
        }),
      )
      .child(this.renderCommitButton())
      .when(Boolean(hint), (el) =>
        el.child(
          div()
            .text_size(TEXT.caption)
            .text_color(this.commitMode === "amend" ? t.working : t.dim)
            .whitespace_normal()
            .child(hint ?? ""),
        ),
      );
  },

  commitBoxHint() {
    if (this.amendLoading) return "Loading the latest commit…";
    if (this.conflicts) return "Resolve conflicts and stage the files before committing.";
    if (this.commitMode === "amend") {
      return "Amend rewrites the latest commit. Unstaged changes stay untouched.";
    }
    return null;
  },

  commitButtonLabel() {
    if (this.operation === "commit") return "Committing…";
    if (this.operation === "amend") return "Amending…";
    return this.commitMode === "amend" ? "Amend" : "Commit";
  },

  renderCommitButton() {
    const amend = this.commitMode === "amend";
    return SplitButton({
      id: "commit",
      icon: amend ? "amend" : "commit",
      label: this.commitButtonLabel(),
      enabled: this.canCommit(),
      primary: !amend,
      onClick: (cx) => this.commit(cx),
      menu: this.renderCommitMenu(),
    });
  },

  renderCommitMenu() {
    const amend = this.commitMode === "amend";
    const choose = (mode) => (cx) => this.setCommitMode(mode, cx);
    const options = [
      MenuOption({
        id: "mode-commit",
        icon: "commit",
        label: "Commit",
        selected: !amend,
        onClick: choose("commit"),
      }),
    ];
    if (this.hasHead) {
      options.push(
        MenuOption({
          id: "mode-amend",
          icon: "amend",
          label: "Amend",
          selected: amend,
          onClick: choose("amend"),
        }),
      );
    }
    return Menu({
      id: "commit-menu",
      open: this.commitMenuOpen,
      focus: this.commitMenuFocus,
      anchor: "bottom_right",
      onOpenChange: (open, cx) => {
        this.commitMenuOpen = open;
        cx.notify();
      },
      trigger: SplitTrigger({ id: "commit-options", label: "Commit options" }),
      children: options,
    });
  },

  addGroup(list, scope, label, files, detail, count = files.length) {
    if (!files.length) return;
    const collapsed = this.collapsed.has(scope);
    const bulk = {
      unstaged: { action: "stage", icon: "plus", label: "Stage all" },
      staged: { action: "unstage", icon: "minus", label: "Unstage all" },
    }[scope];
    list.child(
      GroupHeader({
        id: `group-${scope}`,
        label,
        count,
        detail,
        danger: scope === "conflict",
        collapsed,
        divided: this.groupsDrawn++ > 0,
        action:
          bulk &&
          TextButton({
            id: `${bulk.action}-all`,
            icon: bulk.icon,
            label: bulk.label,
            onClick: (cx) => this.indexAction(bulk.action, null, cx),
          }),
        onClick: (cx) => this.toggleGroup(scope, cx),
      }),
    );
    if (collapsed) return;
    this.addRows(list, scope, files);
  },

  // A group's files, flat or nested as chosen in the options menu.
  addRows(list, scope, files) {
    if (this.view === "flat") {
      for (const file of files) list.child(this.fileRow(file, scope, 0));
      return;
    }
    const closed = new Set(
      [...this.closed]
        .filter((key) => key.startsWith(`${scope}:`))
        .map((key) => key.slice(scope.length + 1)),
    );
    for (const row of fileTree(files, closed))
      list.child(
        row.kind === "folder"
          ? this.folderRow(row, scope, closed.has(row.path))
          : this.fileRow(row.file, scope, row.depth),
      );
  },

  folderRow(row, scope, closed) {
    const t = theme();
    const key = `${scope}:${row.path}`;
    return Row({
      id: `folder-${key}`,
      depth: row.depth,
      stem: !closed,
      onClick: (cx) => {
        if (closed) this.closed.delete(key);
        else this.closed.add(key);
        cx.notify();
      },
    })
      .child(Chevron(!closed))
      .when(Boolean(this.fileIcons), (el) =>
        el.child(FileIcon({ icons: this.fileIcons, path: `${this.root}/${row.path}`, dir: true, open: !closed, t })),
      )
      .child(div().flex_1().min_w(0).truncate().child(row.name));
  },

  fileRow(file, scope, depth) {
    const t = theme();
    const parts = file.path.split("/");
    const name = parts.pop();
    const tree = this.view === "tree";
    const stats =
      scope === "staged" ? file.stagedStats : scope === "unstaged" ? file.unstagedStats : file;
    const status =
      scope === "staged"
        ? file.stagedStatus
        : scope === "unstaged"
          ? file.unstagedStatus
          : file.status;
    const open = shared("better-changes.selection");
    const row = Row({
      id: `file-${scope}-${file.path}`,
      depth,
      selected: open?.path === file.path && open?.scope === scope,
      onClick: (cx) => this.pick(file, scope, cx),
    }).child(FileIcon({ icons: this.fileIcons, path: `${this.root}/${file.path}`, color: t.muted, t }));
    if (tree) row.child(div().flex_1().min_w(0).truncate().child(name));
    else
      row.child(
        h_flex()
          .flex_1()
          .min_w(0)
          .gap(6)
          .items_center()
          .child(div().max_w(190).flex_none().truncate().child(name))
          .child(
            div()
              .flex_1()
              .min_w(0)
              .truncate()
              .text_size(TEXT.small)
              .text_color(t.dim)
              .child(parts.join("/")),
          ),
      );
    if (file.conflict)
      row.child(
        div().flex_none().text_size(TEXT.caption).text_color(t.ansi1).child(file.conflictKind),
      );
    else row.child(DiffStat(stats)).child(StatusLetter(status));
    if (scope === "unstaged")
      row.child(
        IconButton({
          id: `stage-${file.path}`,
          icon: "plus",
          label: "Stage",
          small: true,
          onClick: (cx) => this.indexAction("stage", file.path, cx),
        }),
      );
    if (scope === "staged")
      row.child(
        IconButton({
          id: `unstage-${file.path}`,
          icon: "minus",
          label: "Unstage",
          small: true,
          onClick: (cx) => this.indexAction("unstage", file.path, cx),
        }),
      );
    return row;
  },

  renderHistory() {
    const list = v_flex().id("commit-list").flex_1().min_h(0).overflow_y_scrollbar().p(6);
    if (this.commitsError) return list.child(Message(this.commitsError, true));
    if (!this.commits.length)
      return list.child(
        Message(this.commitsLoading || !this.root ? "Loading history…" : "No commits yet"),
      );
    this.groupsDrawn = 0;
    const remote = this.committed;
    const more = this.commitsDone ? "" : "+";
    const local = this.branch ?? "HEAD";
    if (!remote) {
      this.addCommits(list, {
        scope: "branch",
        label: local,
        count: `${this.commits.length}${more}`,
        commits: this.commits,
        withMore: true,
      });
      return list;
    }
    const notPulled = (n) => (n ? `${n} not pulled` : null);
    const detail = (...parts) => parts.filter(Boolean).join(" · ");
    const head = this.remoteHead;
    const pushed = this.commits.filter((c) => !remote.unpushed.has(c.hash));
    this.addCommits(list, {
      scope: "branch",
      label: local,
      count: remote.unpushed.size,
      commits: this.commits.filter((c) => remote.unpushed.has(c.hash)),
    });
    if (head && head.target !== remote.name) {
      // A feature branch: what the remote branch has, then the default branch under it.
      const onBranch = pushed.filter((c) => head.ahead.has(c.hash));
      const onDefault = pushed.filter((c) => !head.ahead.has(c.hash));
      this.addCommits(list, {
        scope: "remote",
        label: remote.name,
        count: onBranch.length,
        commits: onBranch,
        detail: notPulled(this.behind),
      });
      this.addCommits(list, {
        scope: "default",
        label: head.name,
        count: `${onDefault.length}${more}`,
        commits: onDefault,
        detail: detail(head.target, notPulled(head.behind)),
        withMore: true,
      });
      return list;
    }
    this.addCommits(list, {
      scope: "remote",
      label: remote.name,
      count: `${pushed.length}${more}`,
      commits: pushed,
      detail: detail(head?.name, notPulled(this.behind)),
      withMore: true,
    });
    return list;
  },

  addCommits(list, { scope, label, count, commits, detail, withMore = false }) {
    if (!commits.length) return;
    const t = theme();
    const collapsed = this.collapsed.has(scope);
    list.child(
      GroupHeader({
        id: `group-${scope}`,
        label,
        count,
        detail,
        collapsed,
        divided: this.groupsDrawn++ > 0,
        onClick: (cx) => this.toggleGroup(scope, cx),
      }),
    );
    if (collapsed) return;
    for (const commit of commits) list.child(this.commitRow(commit));
    if (withMore && !this.commitsDone)
      list.child(
        Row({ id: "commits-more", onClick: (cx) => this.loadCommits(cx, true) })
          .justify_center()
          .text_size(TEXT.small)
          .text_color(t.muted)
          .child(this.commitsLoading ? "Loading…" : "Load more"),
      );
  },

  commitRow(commit) {
    const t = theme();
    return h_flex()
      .id(`commit-${commit.hash}`)
      .flex_none()
      .px(8)
      .py(6)
      .gap(8)
      .items_center()
      .rounded(7)
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click((_e, cx) => this.openCommit(commit, cx))
      .child(
        v_flex()
          .flex_1()
          .min_w(0)
          .gap(1)
          .child(div().truncate().child(commit.subject))
          .child(
            div()
              .truncate()
              .text_size(TEXT.caption)
              .text_color(t.dim)
              .child(`${commit.author} · ${timeAgo(commit.at)}`),
          ),
      )
      .child(
        div()
          .flex_none()
          .text_size(TEXT.caption)
          .text_color(t.dim)
          .font_family(codeFont())
          .child(commit.short),
      );
  },

  renderCommit() {
    return v_flex()
      .id("commit-detail")
      .flex_1()
      .min_h(0)
      .child(this.renderCommitTopRow())
      .child(
        v_flex()
          .id("commit-scroll")
          .flex_1()
          .min_h(0)
          .overflow_y_scrollbar()
          .child(this.renderCommitAbout())
          .child(this.renderCommitChanges()),
      );
  },

  // Only a commit the remote has can be opened there.
  commitUrl(commit) {
    if (!this.repo || this.committed?.unpushed.has(commit.hash)) return null;
    return `https://github.com/${this.repo}/commit/${commit.hash}`;
  },

  renderCommitTopRow() {
    const t = theme();
    const commit = this.selectedCommit;
    const url = this.commitUrl(commit);
    const row = PanelHeader()
      .px(8)
      .gap(4)
      .child(
        IconButton({
          id: "commit-back",
          icon: "chevron-left",
          label: "Back to commits",
          onClick: (cx) => {
            this.selectedCommit = null;
            this.commitToken++;
            cx.notify();
          },
        }),
      )
      .child(
        div()
          .flex_1()
          .min_w(0)
          .truncate()
          .text_size(TEXT.small)
          .text_color(t.dim)
          .font_family(codeFont())
          .child(commit.short),
      );
    if (url) {
      row.child(
        IconButton({
          id: "commit-open",
          icon: "external-link",
          label: "Open on GitHub",
          onClick: (cx) => cx.open_url(url),
        }),
      );
    }
    return row;
  },

  renderCommitAbout() {
    const t = theme();
    const commit = this.selectedCommit;
    const when = new Date(commit.at * 1000).toLocaleString();
    const about = v_flex()
      .id("commit-about")
      .flex_none()
      .px(14)
      .py(10)
      .gap(4)
      .border_b(1)
      .border_color(t.border)
      .child(div().font_medium().whitespace_normal().child(commit.subject))
      .child(
        div()
          .text_size(TEXT.caption)
          .text_color(t.dim)
          .whitespace_normal()
          .child(`${commit.author} · ${when}`),
      );
    if (commit.body) {
      about.child(
        div()
          .pt(6)
          .text_size(TEXT.small)
          .text_color(t.muted)
          .whitespace_normal()
          .child(commit.body),
      );
    }
    return about;
  },

  renderCommitChanges() {
    const changes = v_flex().id("commit-changes").flex_none().p(6);
    if (this.commitFilesError) return changes.child(Message(this.commitFilesError, true));
    if (this.commitFilesLoading) return changes.child(Message("Loading changes…"));
    if (this.commitFiles.length) {
      changes.child(
        GroupHeader({ id: "group-commit", label: "Changes", count: this.commitFiles.length }),
      );
    }
    this.addRows(changes, "commit", this.commitFiles);
    return changes;
  },
};
