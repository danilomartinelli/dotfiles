import { div } from "gpui-kit";
import { Button, Checkbox, h_flex, v_flex } from "gpui-base";
import { theme } from "herdr";
import { selectedFindings } from "./report.js";

function button(id, text, click, { label = text, disabled = false } = {}) {
  const t = theme();
  return Button.new(id).flex_none().px(7).py(4).rounded(5).bg(t.raised)
    .text_color(disabled ? t.dim : t.foreground).disabled(disabled)
    .accessibility_label(label).tooltip(label)
    .when(!disabled, (el) => el.cursor_pointer().hover((style) => style.bg(t.hover)))
    .on_click((_event, cx) => click(cx)).child(text);
}

function finding(view, item, index) {
  const t = theme();
  const row = h_flex().gap(7).items_start();
  if (!item.ignored) {
    row.child(Checkbox.new(`select-${index}`).checked(item.selected).cursor_pointer()
      .accessibility_label(`Select finding: ${item.comment}`)
      .on_change((checked, cx) => {
        item.selected = checked;
        view.save();
        cx.notify();
      }).child(div().size(17).rounded(4).border_1().border_color(item.selected ? t.accent : t.border)
        .flex().items_center().justify_center().child(item.selected ? "✓" : "")));
  }
  row.child(div().flex_1().min_w(0).whitespace_normal().child(item.comment));
  row.child(button(`ignore-${index}`, item.ignored ? "Restore" : "Ignore", (cx) => {
    item.ignored = !item.ignored;
    view.save();
    cx.notify();
  }));
  return v_flex().flex_none().py(9).gap(4).border_b(1).border_color(t.border).child(row)
    .children(item.paths.map((path) => div().min_w(0).whitespace_normal().text_size(12)
      .text_color(t.muted).child(path)));
}

export function panel(view) {
  const t = theme();
  const root = v_flex().id("review-findings").size_full().min_w(0).min_h(0)
    .rounded(10).border_1().border_color(t.border).bg(t.background).text_color(t.foreground).text_size(13);
  const ready = Boolean(view.agent && view.store && !view.launching);
  root.child(h_flex().items_center().flex_none().p(8).gap(6).border_b(1).border_color(t.border)
    .child(div().flex_1().font_medium().child("Findings"))
    .child(button("run-review", "Code Review", (cx) => view.launch(true, cx),
      { disabled: !ready || Boolean(view.pending), label: "Start a code review in a new chat" })));
  const list = v_flex().id("findings-list").flex_1().min_h(0).overflow_y_scrollbar().px(10).py(6).gap(4);
  if (view.error) list.child(div().whitespace_normal().child(view.error))
    .child(button("retry-load", "Reload", (cx) => view.load({ ...view.checkout }, cx)));
  if (view.pending) {
    list.child(div().whitespace_normal().text_color(t.muted).child("Waiting for the review report…"))
      .child(button("stop-waiting", "Stop waiting", (cx) => view.stopWaiting(cx)));
    if (view.reportError) list.child(div().whitespace_normal().child(view.reportError));
  }
  if (!view.items.length && !view.pending && !view.error)
    list.child(div().text_color(t.muted).child(view.completed ? "Review complete. No findings." : "No findings yet."));
  const ignored = view.items.filter((item) => item.ignored).length;
  view.items.forEach((item, index) => {
    if (!item.ignored) list.child(finding(view, item, index));
  });
  if (ignored) {
    list.child(button("show-ignored", `${view.ignoredOpen ? "Hide" : "Show"} ignored (${ignored})`, (cx) => {
      view.ignoredOpen = !view.ignoredOpen;
      cx.notify();
    }));
    if (view.ignoredOpen) view.items.forEach((item, index) => {
      if (item.ignored) list.child(finding(view, item, index));
    });
  }
  root.child(list);
  const footer = v_flex().flex_none().p(8).gap(4).border_t(1).border_color(t.border);
  if (view.menu) footer.children(view.agents.map((agent) => button(`agent-${agent.key}`,
    (agent === view.agent ? "✓ " : "") + agent.name, (cx) => view.choose(agent, cx))));
  const count = selectedFindings(view.items).length;
  footer.child(h_flex().items_center().gap(2)
    .child(button("fix", `Diagnose & Fix (${count})`, (cx) => view.launch(false, cx),
      { disabled: !ready || !count }))
    .child(button("choose-agent", "▾", (cx) => { view.menu = !view.menu; cx.notify(); },
      { label: "Choose the chat agent for reviews and fixes", disabled: !view.agents.length }))
    .child(div().ml(5).min_w(0).truncate().text_color(t.muted).child(view.agent?.name ?? "")));
  return root.child(footer);
}
