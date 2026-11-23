// The two lists, and what sits around them: messages, the footer and refresh.
import { div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { theme } from "herdr";
import { person, stateGroups, timeAgo } from "../linear/model.js";
import {
  TEXT,
  Busy,
  Button,
  CodeBlock,
  GroupHeader,
  HeaderTab,
  Icon,
  IconButton,
  IssueRow,
  Message,
  PanelHeader,
  Row,
  SmallButton,
  StateDot,
  TextButton,
  TextField,
} from "./ui.js";

const SCOPES = [
  { id: "mine", label: "My issues" },
  { id: "cycle", label: "Active cycle" },
  { id: "all", label: "All issues" },
];
const STATES = [
  { id: "active", label: "Active" },
  { id: "backlog", label: "Backlog" },
  { id: "started", label: "Started" },
  { id: "done", label: "Done" },
  { id: "cancelled", label: "Cancelled" },
  { id: "all", label: "All states" },
];
const labelOf = (choices, id) => choices.find((c) => c.id === id)?.label ?? "";

export const listMethods = {
  // Errors, confirmations and settings problems, under whichever header is showing.
  messages(root) {
    const t = theme();
    if (this.error)
      root.child(
        h_flex()
          .id("issue-error")
          .flex_none()
          .px(8)
          .gap(8)
          .items_center()
          .child(div().flex_1().min_w(0).child(Message(this.error, true)))
          .child(
            TextButton({
              id: "issue-retry",
              icon: "refresh",
              label: "Retry",
              disabled: this.busy || this.mutating,
              onClick: (cx) => this.refresh(cx),
            }),
          ),
      );
    if (this.notice)
      root.child(
        div().flex_none().px(14).py(5).text_size(TEXT.small).text_color(t.done).child(this.notice),
      );
    if (this.settingsProblems.length)
      root.child(
        div()
          .id("issue-settings-problems")
          .px(14)
          .py(5)
          .flex_none()
          .text_size(TEXT.caption)
          .text_color(t.ansi1)
          .whitespace_normal()
          .child(`mod.json settings: ${this.settingsProblems.join("; ")}`),
      );
    return root;
  },

  refreshButton() {
    return IconButton({
      id: "issue-refresh",
      icon: "refresh",
      label: "Refresh issues",
      spinning: Boolean(this.busy),
      disabled: this.busy || this.mutating,
      onClick: (cx) => this.refresh(cx),
    });
  },

  showView(view, cx) {
    const sole = view === this.view && this.soleBranchIssue();
    if (sole && sole.identifier === this.issue?.identifier) return;
    if (this.issue || this.opening) this.backToList(cx);
    if (this.issue) return; // a write is under way, and leaving waits for it
    this.view = view;
    this.notice = null;
    localStorage.setItem("view", view);
    this.openSoleBranchIssue(cx);
    cx.notify();
  },

  // Waiting on a count not known yet. A refresh of a filter already read keeps its number.
  allCountPending() {
    if (!this.listLoaded || this.searchPending) return true;
    return Boolean(this.loading) && !this.cache[this.listKey()];
  },

  listHeader() {
    return PanelHeader()
      .child(
        h_flex()
          .flex_1()
          .min_w(0)
          .ml(-8) // Lines the pills up with the rows below.
          .gap(4)
          .items_center()
          .role("tab_list")
          .child(
            HeaderTab({
              id: "issue-view-branch",
              label: "Branch",
              count: this.branchIssues.length,
              loading: !this.branchLoaded,
              disabled: !this.branchLoaded,
              active: this.view === "branch",
              onClick: (cx) => this.showView("branch", cx),
            }),
          )
          .child(
            HeaderTab({
              id: "issue-view-all",
              label: "All",
              count: `${this.items.length}${this.cursor ? "+" : ""}`,
              loading: this.allCountPending(),
              disabled: !this.listLoaded,
              active: this.view === "all",
              onClick: (cx) => this.showView("all", cx),
            }),
          ),
      )
      .child(this.refreshButton());
  },

  filters() {
    const t = theme();
    const pick = (id, label, accessibilityLabel, width, choices, value, triggerFocus, onChoose) =>
      this.chooser({
        id,
        label,
        accessibilityLabel,
        anchor: "top_left",
        width,
        choices,
        value,
        triggerFocus,
        onChoose,
      });
    const choosers = h_flex()
      .gap(6)
      .items_center()
      .flex_wrap()
      .child(
        pick(
          "issue-scope",
          labelOf(SCOPES, this.scope),
          "Whose issues",
          150,
          SCOPES,
          this.scope,
          this.scopeTrigger,
          (scope, cx) => {
            this.scope = scope;
            this.loadList(cx);
          },
        ),
      )
      .child(
        pick(
          "issue-state",
          labelOf(STATES, this.state),
          "Workflow state",
          130,
          STATES,
          this.state,
          this.stateTrigger,
          (state, cx) => {
            this.state = state;
            this.loadList(cx);
          },
        ),
      );
    if (this.teams.length > 1) {
      const teams = [
        { id: "any", label: "All teams" },
        ...this.teams.map((team) => ({ id: team.key, label: team.name })),
      ];
      choosers.child(
        pick(
          "issue-team",
          labelOf(teams, this.team || "any"),
          "Team",
          200,
          teams,
          this.team || "any",
          this.teamTrigger,
          (team, cx) => {
            this.team = team === "any" ? "" : team;
            this.loadList(cx);
          },
        ),
      );
    }
    return v_flex()
      .id("issue-filter-row")
      .flex_none()
      .px(14)
      .py(10)
      .gap(8)
      .border_b(1)
      .border_color(t.border)
      .child(h_flex().child(TextField({ id: "issue-search-input", state: this.search })))
      .child(choosers);
  },

  issueRow(issue, t) {
    const owner = person(issue.assignee) || "Unassigned";
    const where = issue.project?.name;
    return IssueRow({
      id: `issue-${issue.id}`,
      icon: StateDot(issue.state?.color),
      title: issue.title,
      identifier: issue.identifier,
      meta: [owner, timeAgo(issue.updatedAt), where].filter(Boolean).join(" · "),
      onClick: (cx) => {
        this.composer = null;
        this.notice = null;
        this.opening = { identifier: issue.identifier };
        this.openIssue(issue.identifier, cx);
        cx.notify();
      },
    });
  },

  // With nothing on the branch, say so and offer to link one.
  branchEmpty() {
    const t = theme();
    const box = v_flex().p(8).gap(10).min_w(0);
    if (!this.branch) return box.child(Message("Check out a branch to see its issue."));
    box.child(Message(`No issue found for ${this.branch}.`));
    return box.child(
      h_flex()
        .id("issue-link-row")
        .px(8)
        .gap(8)
        .items_center()
        .child(TextField({ id: "issue-link-input", state: this.linkInput, height: 28 }))
        .child(
          SmallButton({
            id: "issue-link",
            icon: "link",
            label: "Link issue",
            disabled: this.mutating,
            onClick: (cx) => this.linkIssue(cx),
          }),
        ),
    );
  },

  branchList(t) {
    if (!this.branchIssues.length && this.branchLoading)
      return Busy("Loading this branch's issues…");
    const list = v_flex()
      .id("issue-branch-list")
      .flex_1()
      .min_h(0)
      .overflow_y_scrollbar()
      .p(6)
      .gap(2);
    if (!this.branchIssues.length) return list.child(this.branchEmpty());
    return list.children(this.branchIssues.map((issue) => this.issueRow(issue, t)));
  },

  // Linear does the matching, including identifiers and bare numbers.
  allList(t) {
    if (!this.items.length && this.busy) return Busy("Loading issues…");
    const list = v_flex()
      .id(`issue-list-${this.listKey()}`)
      .flex_1()
      .min_h(0)
      .overflow_y_scrollbar()
      .p(6);
    if (!this.items.length) list.child(Message("No matching issues."));
    stateGroups(this.items).forEach((group, i) => {
      const key = `state:${group.name}`;
      const open = !this.closedGroups.has(key);
      list.child(
        GroupHeader({
          id: `issue-group-${group.name}`,
          label: group.name,
          count: group.items.length,
          icon: StateDot(group.state?.color, 8),
          collapsed: !open,
          divided: i > 0,
          onClick: (cx) => this.toggleGroup(key, cx),
        }),
      );
      if (open) list.children(group.items.map((issue) => this.issueRow(issue, t)));
    });
    if (this.cursor)
      list.child(
        Row({
          id: "issue-more",
          onClick: this.loading || this.searchPending ? null : (cx) => this.loadList(cx, true),
        })
          .justify_center()
          .text_size(TEXT.small)
          .text_color(t.muted)
          .child(this.loading ? "Loading…" : "+ more"),
      );
    return list;
  },

  renderList(root) {
    const t = theme();
    root.child(this.listHeader());
    this.messages(root);
    if (this.view === "all") root.child(this.filters()).child(this.allList(t));
    else root.child(this.branchList(t));
    return root.child(this.footer());
  },

  // Nothing works without a key, so this replaces everything below the tabs.
  renderKeyProblem(root, problem) {
    const t = theme();
    root.child(this.listHeader());
    root.child(
      v_flex()
        .id("issue-key-problem")
        .flex_1()
        .min_h(0)
        .px(24)
        .gap(12)
        .items_center()
        .justify_center()
        .child(Icon("issue", 24).text_color(t.dim))
        .child(div().font_medium().child(problem.title))
        .child(
          div()
            .text_size(TEXT.small)
            .text_color(t.muted)
            .whitespace_normal()
            .text_center()
            .child(problem.detail),
        )
        .child(CodeBlock(problem.command))
        .child(
          h_flex()
            .gap(8)
            .child(
              Button({
                id: "issue-get-key",
                label: "Create a key",
                onClick: (cx) => cx.open_url("https://linear.app/settings/api"),
              }),
            )
            .child(
              Button({
                id: "issue-key-retry",
                label: this.busy ? "Checking…" : "Try again",
                primary: true,
                disabled: this.busy,
                onClick: (cx) => {
                  this.error = null;
                  this.refresh(cx);
                },
              }),
            ),
        ),
    );
    return root.child(this.footer());
  },

  // From opening an issue until it arrives, the content is only this.
  renderOpening(root) {
    root.child(this.listHeader());
    this.messages(root);
    if (this.showsBack(this.opening.identifier))
      root.child(h_flex().flex_none().px(8).py(5).child(this.backButton()));
    root.child(Busy(`Loading ${this.opening.identifier}…`));
    return root.child(this.footer());
  },

  footer() {
    const t = theme();
    return h_flex()
      .id("issue-footer")
      .h(34)
      .flex_none()
      .px(14)
      .gap(8)
      .items_center()
      .border_t(1)
      .border_color(t.border)
      .text_size(TEXT.caption)
      .text_color(t.dim)
      .child(
        div()
          .flex_1()
          .min_w(0)
          .truncate()
          .child(this.branch || (this.branchLoading ? "Finding branch…" : "No branch")),
      )
      .child(
        div()
          .flex_none()
          .tooltip(this.lastUpdated ? new Date(this.lastUpdated).toLocaleString() : "")
          .child(this.busy ? "Updating…" : this.updatedLabel()),
      );
  },
};
