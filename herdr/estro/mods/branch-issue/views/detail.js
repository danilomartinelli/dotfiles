// An issue: its title and numbers, its tabs, and the Overview.
import { div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { theme } from "herdr";
import { issueStats, linkedPRs, person, workflowOrder } from "../linear/model.js";
import { agentName } from "../actions/agents.js";
import {
  TEXT,
  codeFont,
  halfTone,
  GroupHeader,
  Icon,
  IconButton,
  Markdown,
  MenuButton,
  Message,
  Row,
  Stat,
  StateDot,
  SubTab,
} from "./ui.js";

const PRIORITIES = [
  { id: 0, label: "No priority" },
  { id: 1, label: "Urgent" },
  { id: 2, label: "High" },
  { id: 3, label: "Medium" },
  { id: 4, label: "Low" },
];
const AGENT_COLORS = { working: "working", blocked: "blocked", done: "done" };

export const detailMethods = {
  renderDetail(root) {
    const issue = this.issue;
    root.child(this.listHeader());
    this.messages(root);
    root.child(this.about(issue));
    root.child(this.sectionTabs(issue));
    const body = v_flex()
      .id(`issue-detail-${issue.id}-${this.section}`)
      .flex_1()
      .min_w(0)
      .min_h(0)
      .overflow_y_scrollbar()
      .p(6);
    if (this.section === "comments") this.commentsView(body, issue);
    else this.overview(body, issue);
    root.child(body);
    // A handoff from Actions. Docked below the scroll area: gpui-kit can only scroll a virtual list from code.
    if (this.composer && !this.composer.entry) root.child(this.dockedComposer());
    return root.child(this.footer());
  },

  backButton() {
    return IconButton({
      id: "issue-back",
      icon: "chevron-left",
      label: "Back to issues",
      disabled: this.mutating,
      onClick: (cx) => this.backToList(cx),
    });
  },

  // A branch's only issue has no list to go back to.
  showsBack(identifier) {
    return this.soleBranchIssue()?.identifier !== identifier;
  },

  sectionTabs(issue) {
    const t = theme();
    const tab = (id, label, count) =>
      SubTab({
        id: `issue-${id}`,
        label,
        count,
        active: this.section === id,
        onClick: (cx) => this.selectSection(id, cx),
      });
    return h_flex()
      .id("issue-detail-tabs")
      .flex_none()
      .px(14)
      .pt(8)
      .gap(16)
      .items_center()
      .border_b(1)
      .border_color(t.border)
      .role("tab_list")
      .child(tab("overview", "Overview"))
      .child(tab("comments", "Comments", (issue.comments ?? []).length));
  },

  // Starting work, handing it on and undoing a link: what's done to the issue itself.
  actionsMenu(issue) {
    const agents = this.agentChoices();
    const choices = [
      { id: "start", label: "Create worktree" },
      ...agents.flatMap((a, i) => [
        { id: `agent:${a.address}`, label: `Send to ${agentName(a)}`, divided: i === 0 },
        ...(this.spawnRun(a)
          ? [{ id: `agent:spawn:${a.address}`, label: `Send to ${agentName(a)} (spawn)` }]
          : []),
      ]),
      ...this.newAgentChoices().map((a, i) => ({
        id: `agent:${a.address}`,
        label: `Send to ${agentName(a)}`,
        divided: i === 0,
      })),
      ...(this.linkedIdentifiers.has(issue.identifier)
        ? [{ id: "unlink", label: "Unlink from this branch", divided: true }]
        : []),
    ];
    return this.chooser({
      id: "issue-actions",
      accessibilityLabel: "Actions for this issue",
      width: 220,
      trigger: MenuButton({ id: "issue-actions-trigger", label: "Actions" }),
      choices,
      onChoose: (id, cx) => {
        if (id === "start") this.startWork(cx);
        else if (id === "unlink") this.unlinkIssue(issue.identifier, cx);
        else this.compose("agent", null, null, cx, { target: id.slice("agent:".length) });
      },
    });
  },

  startWork(cx) {
    this.section = "overview";
    this.closedGroups.delete("worktrees");
    this.showWorktree(cx);
  },

  // Fixed above the tabs, so where things stand stays in sight. The Linear link sits
  // with the title it opens.
  about(issue) {
    const t = theme();
    return v_flex()
      .id("issue-about")
      .flex_none()
      .px(14)
      .pt(10)
      .pb(4)
      .gap(6)
      .child(
        h_flex()
          .gap(8)
          .min_w(0)
          .items_center()
          .when(this.showsBack(issue.identifier), (el) => el.child(this.backButton().ml(-6)))
          .child(StateDot(issue.state?.color))
          .child(
            h_flex()
              .flex_1()
              .min_w(0)
              .gap(6)
              .child(div().min_w(0).font_medium().whitespace_normal().child(issue.title))
              .child(
                div().flex_none().text_color(t.dim).font_family(codeFont()).child(issue.identifier),
              ),
          )
          .child(
            IconButton({
              id: "issue-open-linear",
              icon: "external",
              label: "Open in Linear",
              onClick: (cx) => cx.open_url(issue.url),
            }).mr(-6),
          ),
      )
      .child(
        h_flex()
          .gap(8)
          .min_h(26)
          .items_center()
          .child(
            div()
              .flex_1()
              .min_w(0)
              .truncate()
              .text_size(TEXT.caption)
              .text_color(t.dim)
              .child(issue.team?.name ?? ""),
          )
          .child(this.actionsMenu(issue)),
      )
      .child(this.summary(issue));
  },

  // The same numbers on every issue. Each opens where it's explained.
  // What's quickest to change, then how far along it is when there's anything to say.
  summary(issue) {
    const t = theme();
    const box = v_flex().id("issue-stats").px(10).py(4).gap(2).rounded(6).bg(halfTone(t.raised));
    box.child(this.propertyLine(issue));
    const stats = issueStats(issue);
    if (!stats.length) return box;
    const COLORS = { danger: t.ansi1, waiting: t.ansi3, good: t.ansi2, none: t.muted };
    const line = h_flex().min_h(24).gap(8).flex_wrap().items_center();
    stats.forEach((stat, i) => {
      if (i) line.child(div().text_color(t.dim).child("·"));
      line.child(
        Stat({
          id: `issue-stat-${stat.key}`,
          value: stat.value,
          label: stat.label,
          color: COLORS[stat.tone],
          detail: stat.detail,
        }),
      );
    });
    return box.child(line);
  },

  // State, priority and assignee, each writing on choice. Their values say what they
  // are, which leaves room for all three on a sidebar's line.
  propertyLine(issue) {
    const t = theme();
    const pick = (options) => this.chooser({ quiet: true, width: 200, ...options });
    const states = workflowOrder(issue.team?.states ?? []).map((s) => ({
      id: s.id,
      label: s.name,
    }));
    const members = [
      ...(this.me ? [{ id: this.me.id, label: "Me" }] : []),
      { id: "none", label: "Unassigned" },
      ...(issue.team?.members ?? [])
        .filter((m) => m.active !== false && m.id !== this.me?.id)
        .map((m) => ({ id: m.id, label: person(m) })),
    ];
    const dot = () => div().flex_none().text_color(t.dim).child("·");
    const priorityColor = { 1: t.ansi1, 2: t.ansi3 }[issue.priority];
    return h_flex()
      .min_h(24)
      .mx(-4) // Lines the values up with the strip's edges, past their hover padding.
      .gap(4)
      .flex_wrap()
      .items_center()
      .child(
        pick({
          id: "issue-state-pick",
          icon: "state",
          label: issue.state?.name ?? "None",
          accessibilityLabel: "State",
          anchor: "top_left",
          choices: states,
          value: issue.state?.id,
          triggerFocus: this.statePick,
          onChoose: (stateId, cx) => this.update({ stateId }, "State", cx),
        }),
      )
      .child(dot())
      .child(
        pick({
          id: "issue-priority-pick",
          icon: "priority",
          label: issue.priorityLabel || "No priority",
          accessibilityLabel: "Priority",
          anchor: "top_left",
          color: priorityColor,
          choices: PRIORITIES,
          value: issue.priority,
          triggerFocus: this.priorityPick,
          onChoose: (priority, cx) => this.update({ priority }, "Priority", cx),
        }),
      )
      .child(div().flex_1())
      .child(
        pick({
          id: "issue-assignee-pick",
          icon: "user",
          label: person(issue.assignee) || "Unassigned",
          accessibilityLabel: "Assignee",
          choices: members,
          value: issue.assignee?.id ?? "none",
          triggerFocus: this.assigneePick,
          onChoose: (id, cx) =>
            this.update(id === "none" ? { unassign: true } : { assignee: id }, "Assignee", cx),
        }),
      );
  },

  // A collapsible part of the Overview; the first has no rule above it.
  group(body, { key, label, count, action }, fill) {
    const open = !this.closedGroups.has(key);
    body.child(
      GroupHeader({
        id: `issue-group-${key}`,
        label,
        count,
        action,
        collapsed: !open,
        divided: this.groupsDrawn++ > 0,
        onClick: (cx) => this.toggleGroup(key, cx),
      }),
    );
    if (open) fill(body);
  },

  overview(body, issue) {
    this.groupsDrawn = 0;
    this.agentRows(body);
    this.worktreeRows(body);
    this.propertyRows(body, issue);
    this.linkRows(body, issue);
    this.childRows(body, issue);
    if (issue.parent)
      this.group(body, { key: "parent", label: "Parent" }, (into) =>
        into.child(
          Row({ id: "issue-parent", onClick: (cx) => this.openRelated(issue.parent, cx) })
            .child(div().flex_1().min_w(0).truncate().child(issue.parent.title))
            .child(
              div()
                .flex_none()
                .text_size(TEXT.caption)
                .text_color(theme().dim)
                .font_family(codeFont())
                .child(issue.parent.identifier),
            ),
        ),
      );
    this.group(body, { key: "description", label: "Description" }, (into) =>
      into.child(
        div()
          .px(8)
          .pt(2)
          .pb(10)
          .min_w(0)
          .child(Markdown(`issue-description-${issue.id}`, issue.description || "No description.")),
      ),
    );
  },

  openRelated(related, cx) {
    this.opening = { identifier: related.identifier };
    this.issue = null;
    this.openIssue(related.identifier, cx);
    cx.notify();
  },

  agentRows(body) {
    const t = theme();
    const list = this.issueAgents();
    if (!list.length) return;
    this.group(body, { key: "agents", label: "Agents", count: list.length }, (into) => {
      for (const agent of list)
        into.child(
          Row({ id: `issue-agent-${agent.address}`, onClick: () => this.focusAgent(agent) })
            .tooltip("Go to this agent")
            .child(
              div()
                .size(8)
                .flex_none()
                .mx(3)
                .rounded(4)
                .bg(t[AGENT_COLORS[agent.status] ?? "dim"]),
            )
            .child(div().flex_1().min_w(0).truncate().child(agentName(agent)))
            .child(div().flex_none().text_size(TEXT.caption).text_color(t.dim).child(agent.status)),
        );
    });
  },

  // State, priority and assignee write as soon as they're chosen.
  // What can't be changed here, for reading.
  propertyRows(body, issue) {
    const t = theme();
    const row = (id, label, value) =>
      value &&
      Row({ id: `issue-prop-${id}` })
        .child(div().flex_1().min_w(0).text_size(TEXT.small).text_color(t.dim).child(label))
        .child(div().min_w(0).truncate().text_size(TEXT.small).text_color(t.muted).child(value));
    const labels = (issue.labels ?? []).map((l) => l.name).join(", ");
    const rows = [
      row("labels", "Labels", labels),
      row("project", "Project", issue.project?.name),
      row(
        "cycle",
        "Cycle",
        issue.cycle?.name || (issue.cycle?.number && `Cycle ${issue.cycle.number}`),
      ),
      row("estimate", "Estimate", issue.estimate ? String(issue.estimate) : ""),
    ].filter(Boolean);
    if (!rows.length) return;
    this.group(body, { key: "properties", label: "Properties" }, (into) => into.children(rows));
  },

  linkRows(body, issue) {
    const t = theme();
    const links = issue.attachments ?? [];
    if (!links.length) return;
    const prs = new Map(linkedPRs(issue).map((pr) => [pr.id, pr]));
    this.group(body, { key: "links", label: "Links", count: links.length }, (into) => {
      for (const link of links) {
        const pr = prs.get(link.id);
        const COLORS = { danger: t.ansi1, waiting: t.ansi3, good: t.ansi2, none: t.dim };
        into.child(
          Row({ id: `issue-link-${link.id}`, onClick: (cx) => cx.open_url(link.url) })
            .tooltip(link.url)
            .child(Icon("link", 13).text_color(t.muted))
            .child(
              div()
                .flex_1()
                .min_w(0)
                .truncate()
                .child(link.title || link.url),
            )
            .when(Boolean(pr), (el) =>
              el.child(
                div()
                  .flex_none()
                  .text_size(TEXT.caption)
                  .text_color(COLORS[pr.tone])
                  .child(pr.label),
              ),
            ),
        );
      }
    });
  },

  childRows(body, issue) {
    const t = theme();
    const children = issue.children ?? [];
    if (!children.length) return;
    this.group(body, { key: "children", label: "Sub-issues", count: children.length }, (into) => {
      for (const child of children)
        into.child(
          Row({ id: `issue-child-${child.id}`, onClick: (cx) => this.openRelated(child, cx) })
            .child(StateDot(child.state?.color, 8))
            .child(div().flex_1().min_w(0).truncate().child(child.title))
            .child(
              div()
                .flex_none()
                .text_size(TEXT.caption)
                .text_color(t.dim)
                .font_family(codeFont())
                .child(child.identifier),
            ),
        );
    });
  },
};
