import { div } from "gpui-kit";
import { v_flex } from "gpui-base";
import { theme } from "herdr";
import { Busy, GroupHeader, Icon, IconButton, Message, PanelHeader, Row } from "../views/ui.js";

function issueSection(list, id, label, issues, repository, empty) {
  list.child(GroupHeader({ id, label, count: issues.length }));
  if (!issues.length && empty) return list.child(Message(empty));
  const t = theme();
  return list.children(issues.map((issue) => {
    const prefix = issue.repository === repository ? "" : issue.repository;
    return Row({
      id: `${id}-${issue.repository}#${issue.number}`,
      onClick: (cx) => cx.open_url(issue.url),
    })
      .child(div().flex_none().text_color(t.muted).child(`${prefix}#${issue.number}`))
      .child(div().flex_1().min_w(0).truncate().child(issue.title))
      .child(Icon("external", 12));
  }));
}

export function renderGitHubPanel(root, { data, error, loading }, settingsProblems, refresh) {
  root.child(PanelHeader()
    .child(div().flex_1().min_w(0).truncate().child("GitHub Issues"))
    .child(IconButton({
      id: "issue-refresh",
      icon: "refresh",
      label: "Refresh issues",
      spinning: loading,
      disabled: loading,
      onClick: refresh,
    })));
  if (settingsProblems.length)
    root.child(Message(`mod.json settings: ${settingsProblems.join("; ")}`, true));
  if (loading && !data) return root.child(Busy("Loading GitHub issues…"));
  const list = v_flex().id("github-issue-list").flex_1().min_h(0).overflow_y_scrollbar().p(6);
  if (error) list.child(Message(error, true).id("github-issue-error"));
  if (!data) {
    if (!error) list.child(Message("No active checkout."));
    return root.child(list);
  }
  const { repository, linked, items, linkedWarning } = data;
  list.child(Message(repository));
  issueSection(list, "github-linked", "Linked to this checkout", linked, repository,
    linkedWarning ? null : "No linked issues.");
  if (linkedWarning) list.child(Message(linkedWarning, true).id("github-linked-warning"));
  issueSection(list, "github-open", "Open issues", items, repository, "No open issues.");
  return root.child(list);
}
