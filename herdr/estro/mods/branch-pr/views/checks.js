// The Checks tab: workflows, their checks, steps and failed output, and handing
// a failure to an agent.
import { div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { theme } from "herdr";
import {
  checkGroups,
  checkStatus,
  checkSummary,
  cleanLog,
  elapsed,
  jobIdOf,
} from "../github/model.js";
import { TEXT, Chevron, CodeBlock, GroupHeader, Icon, Message, Row, TextButton } from "./ui.js";

export const checksMethods = {
  checkIcon(status, t) {
    return Icon(`check-${status.kind}`, 14)
      .text_color(t[status.color])
      .accessibility_label(status.label)
      .when(status.kind === "running", (el) => el.spin(1400));
  },

  checksView(pr) {
    const t = theme();
    const root = v_flex().id("pr-checks-workflows").min_w(0);
    if (pr.checksError) root.child(Message(pr.checksError, true));
    const checks = pr.checks ?? [];
    if (!checks.length && !pr.checksError) root.child(Message("No checks reported."));
    checkGroups(checks).forEach((group, i) => {
      const summary = checkSummary(group.checks.map((x) => x.check));
      const open = this.workflowOpen[group.key] ?? Boolean(summary.counts.failure);
      root.child(
        GroupHeader({
          id: `workflow-toggle-${group.key}`,
          label: group.name,
          count: group.checks.length,
          icon: this.checkIcon(summary.status, t),
          collapsed: !open,
          divided: i > 0,
          onClick: (cx) => {
            this.workflowOpen[group.key] = !open;
            this.rememberDetail();
            cx.notify();
          },
        }),
      );
      if (open) for (const item of group.checks) this.checkRow(root, pr, group, item, t);
    });
    return root;
  },

  checkRow(root, pr, group, { check, index }, t) {
    const key = `${pr.id}:${index}`;
    const state = checkStatus(check);
    const expanded = Boolean(this.checkOpen[key]);
    const name = check.name || check.context;
    root.child(
      Row({
        id: `check-toggle-${index}`,
        onClick: (cx) => {
          this.checkOpen[key] = !expanded;
          if (
            !expanded &&
            group.run &&
            !this.jobs[group.run]?.jobs &&
            !this.jobs[group.run]?.loading
          )
            this.loadJobs(check, cx);
          this.rememberDetail();
          cx.notify();
        },
      })
        .child(Chevron(expanded))
        .child(this.checkIcon(state, t))
        .child(div().flex_1().min_w(0).truncate().tooltip(name).child(name))
        .when(state.kind === "failure", (el) =>
          el.child(
            this.agentButton({
              id: `pr-fix-${index}`,
              label: "Fix with agent",
              send: (agent, cx) => this.fixCheck(check, agent, cx),
            }),
          ),
        )
        .when(state.kind !== "failure", (el) =>
          el.child(
            div()
              .flex_none()
              .text_size(TEXT.caption)
              .text_color(t.dim)
              .child(elapsed(check.startedAt, check.completedAt) || state.label),
          ),
        ),
    );
    if (expanded) root.child(this.checkDetail(group, check, t));
  },

  checkDetail(group, check, t) {
    const content = v_flex().flex_none().pl(28).pr(8).py(4).gap(2).min_w(0);
    const url = check.detailsUrl || check.targetUrl;
    if (/^https:\/\//.test(url ?? ""))
      content.child(
        TextButton({
          id: `check-open-${url}`,
          label: "View on GitHub",
          onClick: (cx) => cx.open_url(url),
        }),
      );
    const loaded = this.jobs[group.run];
    if (loaded?.loading) content.child(Message("Loading job steps…"));
    if (loaded?.error) content.child(Message(loaded.error, true));
    const jobId = jobIdOf(check);
    const jobs = (loaded?.jobs ?? []).filter((job) =>
      jobId ? String(job.id) === jobId : job.name === check.name,
    );
    if (group.run && loaded?.jobs && !jobs.length)
      content.child(Message("Step details are unavailable. View the workflow on GitHub."));
    for (const job of jobs) this.jobBlock(content, job, t);
    return content;
  },

  jobBlock(content, job, t) {
    for (const step of job.steps ?? [])
      content.child(
        h_flex()
          .h(24)
          .flex_none()
          .gap(6)
          .items_center()
          .text_size(TEXT.small)
          .child(this.checkIcon(checkStatus(step), t))
          .child(div().flex_1().min_w(0).truncate().child(step.name))
          .child(
            div()
              .flex_none()
              .text_size(TEXT.caption)
              .text_color(t.dim)
              .child(elapsed(step.started_at, step.completed_at)),
          ),
      );
    if (job.conclusion === "failure")
      content.child(
        TextButton({
          id: `pr-log-${job.id}`,
          label: "Failed step output",
          disabled: Boolean(this.logs[job.id]?.loading),
          onClick: (cx) => this.loadLogs(job, cx),
        }),
      );
    const log = this.logs[job.id];
    if (log?.error) content.child(Message(log.error, true));
    if (log?.text !== undefined)
      content.child(
        CodeBlock(
          `${log.truncated ? "Last part of the output:\n" : ""}${cleanLog(log.text) || "No failed-step output available."}`,
        ),
      );
  },
};
