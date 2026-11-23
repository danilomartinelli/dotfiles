// A PR: its tabs, what stands in the way of merging it, and the Overview tab.
import { div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { theme } from "herdr";
import {
  REVIEW_STATES,
  STATE_CHANGES,
  checkSummary,
  conversationEntries,
  mergeBlockers,
  prStats,
  prStatus,
  stateEvents,
  who,
} from "../github/model.js";
import { agentName } from "../actions/agents.js";
import { stateIcon } from "./list.js";
import {
  TEXT,
  codeFont,
  halfTone,
  Button,
  Stat,
  GroupHeader,
  SubTab,
  Icon,
  IconButton,
  Markdown,
  MenuButton,
  Message,
  PanelHeader,
  Row,
  TextBox,
} from "./ui.js";

const DECISIONS = {
  APPROVED: { label: "Approved", color: "ansi2" },
  CHANGES_REQUESTED: { label: "Changes requested", color: "ansi1" },
  REVIEW_REQUIRED: { label: "Review required", color: "ansi3" },
};
const AGENT_COLORS = { working: "working", blocked: "blocked", done: "done" };

export const detailMethods = {
  renderDetail(root) {
    const pr = this.pr;
    root.child(this.listHeader());
    this.messages(root);
    root.child(this.about(pr));
    const confirm = this.stateChangeView(pr);
    if (confirm) root.child(confirm);
    root.child(this.sectionTabs(pr));
    if (this.section === "conversation") root.child(this.conversationFilters(pr));
    const body = v_flex()
      .id(`pr-detail-${pr.repository}-${pr.id}-${this.section}`)
      .flex_1()
      .min_w(0)
      .min_h(0)
      .overflow_y_scrollbar()
      .p(6);
    if (this.section === "checks") body.child(this.checksView(pr));
    else if (this.section === "files") this.filesView(body);
    else if (this.section === "conversation") this.conversationView(body, pr);
    else this.overview(body, pr);
    root.child(body);
    // A handoff of several comments. Docked below the scroll area: gpui-kit can only scroll a virtual list from code.
    if (this.composer && !this.composer.entry) root.child(this.dockedComposer());
    return root.child(this.footer());
  },

  // General to specific: the way to all PRs, then this PR, then the part of it below.
  // The shape of a commit's page: back, what this is, and the way out to GitHub.
  backButton() {
    return IconButton({
      id: "pr-back",
      icon: "chevron-left",
      label: "Back to pull requests",
      disabled: this.mutating,
      onClick: (cx) => this.backToList(cx),
    });
  },

  // A branch's only PR has no list to go back to.
  showsBack(number) {
    return this.soleBranchPR()?.number !== number;
  },

  sectionTabs(pr) {
    const t = theme();
    const checks = pr.checks ?? [];
    const tab = (id, label, count, icon) =>
      SubTab({
        id: `pr-${id}`,
        label,
        count,
        icon,
        active: this.section === id,
        onClick: (cx) => this.selectSection(id, cx),
      });
    const summary = checks.length ? checkSummary(checks).status : null;
    return h_flex()
      .id("pr-detail-tabs")
      .flex_none()
      .px(14)
      .pt(8)
      .gap(16)
      .items_center()
      .border_b(1)
      .border_color(t.border)
      .role("tab_list")
      .child(tab("overview", "Overview"))
      .child(tab("conversation", "Comments", conversationEntries(pr).length))
      .child(tab("checks", "Checks", summary ? null : 0, summary && this.checkIcon(summary, t)))
      .child(tab("files", "Files", pr.changedFiles ?? 0));
  },

  // Fixed above the tabs, so what to do next stays in sight.
  // Fixed above the tabs, so what to do next stays in sight. The GitHub link sits
  // with the title it opens, and Actions with the branches they'd affect.
  about(pr) {
    const t = theme();
    const actions = this.actionsMenu(pr);
    return v_flex()
      .id("pr-about")
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
          .when(this.showsBack(pr.number), (el) => el.child(this.backButton().ml(-6)))
          .child(stateIcon(prStatus(pr), t))
          .child(
            h_flex()
              .flex_1()
              .min_w(0)
              .gap(6)
              .child(div().min_w(0).font_medium().whitespace_normal().child(pr.title))
              .child(
                div().flex_none().text_color(t.dim).font_family(codeFont()).child(`#${pr.number}`),
              ),
          )
          .child(
            IconButton({
              id: "pr-detail-github",
              icon: "github",
              label: "Open on GitHub",
              onClick: (cx) => cx.open_url(pr.url),
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
              .tooltip(`${pr.headRefName} → ${pr.baseRefName}`)
              .child(`${who(pr)} · ${pr.headRefName} → ${pr.baseRefName}`),
          )
          .when(Boolean(actions), (el) => el.child(actions))
          .when(pr.state === "MERGED", (el) => el.child(this.mergedBadge(t))),
      )
      .when(pr.state === "OPEN", (el) => el.child(this.blockedBy(pr)));
  },

  // Where Actions would be: a merged PR has nothing left to do.
  mergedBadge(t) {
    return h_flex()
      .id("pr-merged")
      .flex_none()
      .h(26)
      .px(8)
      .gap(5)
      .items_center()
      .rounded(6)
      .border_1()
      .border_color(t.ansi5)
      .text_color(t.ansi5)
      .text_size(TEXT.small)
      .font_medium()
      .child(Icon("merged", 12))
      .child("Merged");
  },

  goToBlocker(blocker, cx) {
    if (blocker.unresolved) {
      this.unresolved = true;
      this.author = "";
    }
    this.selectSection(blocker.section, cx);
  },

  // Why this can't merge yet, each reason a link to where it's explained.
  // Why this can't merge yet, each reason a link to where it's explained.
  // The same numbers on every open PR. Each opens where it's explained.
  blockedBy(pr) {
    const t = theme();
    const COLORS = { danger: t.ansi1, waiting: t.ansi3, good: t.ansi2, none: t.muted };
    const stats = prStats(pr);
    return h_flex()
      .id("pr-stats")
      .px(10)
      .py(6)
      .gap(8)
      .flex_wrap()
      .items_center()
      .rounded(6)
      .bg(halfTone(t.raised))
      .children(
        stats.map((stat, i) =>
          // A dot stays with the stat before it, so none starts a wrapped line.
          h_flex()
            .flex_none()
            .gap(8)
            .items_center()
            .child(
              Stat({
                id: `pr-stat-${stat.key}`,
                value: stat.value,
                label: stat.label,
                color: COLORS[stat.tone],
                detail: stat.detail,
                onClick: stat.section ? (cx) => this.goToBlocker(stat, cx) : null,
              }),
            )
            .when(i < stats.length - 1, (el) => el.child(div().text_color(t.dim).child("·"))),
        ),
      );
  },

  overview(body, pr) {
    this.agentRows(body);
    this.reviewerRows(body, pr);
    this.worktreeRows(body);
    this.group(body, { key: "description", label: "Description" }, (into) =>
      into.child(
        div()
          .px(8)
          .pt(2)
          .pb(10)
          .min_w(0)
          .child(Markdown(`pr-description-${pr.id}`, pr.body || "No description provided.")),
      ),
    );
  },

  // A collapsible part of the Overview; the first has no rule above it.
  group(body, { key, label, count, action }, fill) {
    const open = !this.closedGroups.has(key);
    body.child(
      GroupHeader({
        id: `pr-group-${key}`,
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

  // Everything that can be done to the PR, the likeliest first. Close and Reopen
  // sit apart, since they don't merge.
  actionsMenu(pr) {
    const events = stateEvents(pr);
    if (!events.length || this.mutating) return null;
    return this.chooser({
      id: "pr-actions",
      accessibilityLabel: "Actions for this pull request",
      width: 220,
      trigger: MenuButton({ id: "pr-actions-trigger", label: "Actions" }),
      choices: events.map((id, i) => ({
        id,
        label: STATE_CHANGES[id].label,
        divided: i > 0 && (id === "close" || id === "reopen"),
      })),
      onChoose: (id, cx) => this.askStateChange(id, cx),
    });
  },

  stateChangeView(pr) {
    const t = theme();
    const change = this.stateChange;
    if (!change || change.repo !== this.repo || change.number !== pr.number) return null;
    const { label, question } = STATE_CHANGES[change.event];
    const squash = change.event === "squash";
    const merging = ["merge", "squash", "rebase"].includes(change.event);
    const warning = merging ? mergeBlockers(pr).map((b) => b.label) : [];
    return (
      v_flex()
        .id("pr-change-confirm")
        .flex_none()
        .mx(14)
        .my(10)
        .p(10)
        .gap(8)
        .rounded(8)
        .border_1()
        .border_color(t.border)
        .bg(t.raised)
        .child(div().min_w(0).whitespace_normal().text_size(TEXT.small).child(question(pr)))
        // GitHub merges past anything it doesn't require, so say so before it does.
        .when(warning.length > 0, (el) =>
          el.child(
            div()
              .min_w(0)
              .whitespace_normal()
              .text_size(TEXT.small)
              .text_color(t.ansi1)
              .child(`Still in the way: ${warning.join(", ")}.`),
          ),
        )
        .when(squash, (el) =>
          el.child(
            TextBox({
              id: "pr-squash-message",
              state: this.squashMessage,
              label: "Commit message",
              height: 130,
            }),
          ),
        )
        .child(
          h_flex()
            .gap(8)
            .justify_end()
            .child(
              Button({
                id: "pr-change-cancel",
                label: "Cancel",
                disabled: this.mutating,
                onClick: (cx) => {
                  this.stateChange = null;
                  cx.notify();
                },
              }),
            )
            .child(
              Button({
                id: "pr-change-yes",
                label,
                primary: true,
                disabled: this.mutating || (squash && !this.squashMessage.value().trim()),
                onClick: (cx) => this.changeState(cx),
              }),
            ),
        )
    );
  },

  agentRows(body) {
    const t = theme();
    const list = this.prAgents();
    this.groupsDrawn = 0;
    if (!list.length) return;
    this.group(body, { key: "agents", label: "Agents", count: list.length }, (into) => {
      for (const agent of list)
        into.child(
          Row({ id: `pr-agent-${agent.address}`, onClick: () => this.focusAgent(agent) })
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

  reviewerRows(body, pr) {
    const t = theme();
    const decision = DECISIONS[pr.reviewDecision];
    const open = pr.state === "OPEN";
    const action =
      decision && div().flex_none().text_color(t[decision.color]).child(decision.label);
    const info = { key: "reviewers", label: "Reviewers", count: pr.reviewers?.length ?? 0, action };
    this.group(body, info, (into) => {
      if (pr.reviewersError) into.child(Message("Could not read reviewers."));
      else if (!pr.reviewers?.length) into.child(Message("No reviewers yet."));
      for (const reviewer of pr.reviewers ?? []) {
        const state = REVIEW_STATES[reviewer.state] ?? REVIEW_STATES.REQUESTED;
        into.child(
          Row({ id: `pr-reviewer-${reviewer.login}` })
            .child(Icon(state.icon).text_color(t[state.color]).accessibility_label(state.label))
            .child(div().flex_1().min_w(0).truncate().tooltip(reviewer.login).child(reviewer.login))
            .child(div().flex_none().text_size(TEXT.caption).text_color(t.dim).child(state.label))
            .when(open && reviewer.state !== "REQUESTED", (el) =>
              el.child(
                IconButton({
                  id: `pr-reviewer-again-${reviewer.login}`,
                  icon: "refresh",
                  label: `Ask ${reviewer.login} to review again`,
                  disabled: this.mutating,
                  onClick: (cx) => this.requestReviewAgain(reviewer.login, cx),
                }),
              ),
            ),
        );
      }
    });
  },
};
