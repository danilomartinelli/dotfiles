// The design kit: Herdr's own conventions, measured from its shipped mods, as
// tokens and small components, with only what this mod uses. UI only: values in,
// callbacks out. Components return ordinary elements, so callers can chain.
import { div, image, svg } from "gpui-kit";
import { h_flex, v_flex, Input, Popover, Textarea, TextView } from "gpui-base";
import { theme, settings } from "herdr";
import { fileIcon, isLight } from "../files/file-icons.js";

// Plain px: Herdr scales a mod's sizes by zoom itself.
export const TEXT = { badge: 10, caption: 11, small: 12, tab: 12.8, body: 13 };
// One turn of a spinning icon, the speed of Herdr's own spinner.
export const SPIN_MS = 900;

export const codeFont = () => settings().font_family ?? "JetBrains Mono";
// The terminals' size, so a file reads like the terminal beside it.
export const codeSize = () => settings().font_size ?? 14;

export const Icon = (name, size = 14) =>
  svg(`mods/better-files/icons/${name}.svg`).size(size).flex_none();

// A file's or folder's icon: Better Icons' full-colour one when it's installed, else this
// mod's own, tinted. t: the theme the caller already holds, so a row asks Herdr for nothing more.
export function FileIcon({ icons, path, dir = false, open = false, color, t, size = 14 }) {
  const picture = fileIcon(icons, path, { dir, open, light: isLight(t.background) });
  return picture ? image(picture).size(size).flex_none() : Icon(dir ? "folder" : "file", size).text_color(color);
}

// A sidebar panel's frame.
export function Panel({ id }) {
  const t = theme();
  return v_flex()
    .id(id)
    .size_full()
    .min_w(0)
    .min_h(0)
    .overflow_hidden()
    .bg(t.background)
    .text_color(t.foreground)
    .text_size(TEXT.body)
    .rounded(10)
    .border_1()
    .border_color(t.border);
}

export function PanelHeader() {
  const t = theme();
  return h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border);
}

export function Badge(text) {
  const t = theme();
  return div()
    .flex_none()
    .px(5)
    .py(1)
    .rounded(4)
    .border_1()
    .border_color(t.border)
    .text_size(TEXT.badge)
    .text_color(t.muted)
    .child(String(text));
}

export function IconButton({
  id,
  icon,
  label,
  onClick,
  disabled = false,
  spinning = false,
  small = false,
}) {
  const t = theme();
  return div()
    .id(id)
    .size(small ? 22 : 26)
    .flex_none()
    .flex()
    .items_center()
    .justify_center()
    .rounded(6)
    .text_color(t.dim)
    .accessibility_label(label)
    .tooltip(label)
    .when(!disabled, (el) =>
      el
        .cursor_pointer()
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_click((_e, cx) => {
          cx.stop_propagation();
          onClick(cx);
        }),
    )
    .child(spinning ? Icon(icon, 15).spin(SPIN_MS) : Icon(icon, small ? 13 : 15));
}

// A small labelled action, for a row with room to say what it does.
export function TextButton({ id, icon, label, onClick, disabled = false, active = false }) {
  const t = theme();
  return h_flex()
    .id(id)
    .h(22)
    .flex_none()
    .px(6)
    .gap(4)
    .items_center()
    .rounded(4)
    .text_size(TEXT.caption)
    .text_color(active ? t.foreground : t.dim)
    .when(active, (el) => el.bg(t.selected))
    .when(!disabled, (el) =>
      el
        .cursor_pointer()
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_click((_e, cx) => {
          cx.stop_propagation();
          onClick(cx);
        }),
    )
    .when(Boolean(icon), (el) => el.child(Icon(icon, 12)))
    .child(label);
}

// A full-size action. `primary` is the solid one; a view has at most one.
export function Button({ id, icon, label, onClick, primary = false, disabled = false }) {
  const t = theme();
  const solid = primary && !disabled;
  return h_flex()
    .id(id)
    .h(32)
    .flex_none()
    .px(14)
    .gap(7)
    .items_center()
    .justify_center()
    .rounded(8)
    .text_size(TEXT.small)
    .bg(solid ? t.solid : t.raised)
    .text_color(solid ? t.solid_foreground : disabled ? t.dim : t.foreground)
    .accessibility_label(label)
    .when(!disabled, (el) =>
      el
        .cursor_pointer()
        .hover((s) => (solid ? s.opacity(0.88) : s.bg(t.hover)))
        .on_click((_e, cx) => onClick(cx)),
    )
    .when(Boolean(icon), (el) => el.child(Icon(icon, 14)))
    .child(label);
}

// The same, as the trigger of a menu.
export function MenuButton({ id, label }) {
  const t = theme();
  return h_flex()
    .id(id)
    .h(26)
    .flex_none()
    .px(8)
    .gap(5)
    .items_center()
    .rounded(6)
    .border_1()
    .border_color(t.border)
    .text_size(TEXT.small)
    .cursor_pointer()
    .accessibility_label(label)
    .hover((s) => s.bg(t.hover))
    .child(label)
    .child(Icon("chevron-down", 11).text_color(t.dim));
}

export function Chevron(open) {
  const t = theme();
  return div()
    .w(14)
    .flex_none()
    .flex()
    .items_center()
    .justify_center()
    .text_color(t.dim)
    .child(Icon(open ? "chevron-down" : "chevron-right", 12));
}

export function Message(text, error = false) {
  const t = theme();
  return div()
    .flex_none()
    .p(8)
    .text_size(TEXT.small)
    .whitespace_normal()
    .text_color(error ? t.ansi1 : t.dim)
    .child(text);
}

// Rendered Markdown, selectable, in Herdr's own TextView, the way its PR mod shows a description.
export const Markdown = (id, text) =>
  TextView.markdown(id, text).text_size(TEXT.body).w_full().min_w(0).scrollable(false).selectable(true);

// One line of text, such as the filter, the way Branch PR draws its search.
export function TextField({ id, state, height = 28 }) {
  const t = theme();
  return Input.new(state)
    .id(id)
    .flex_1()
    .min_w(0)
    .h(height)
    .px(10)
    .rounded(8)
    .border_1()
    .border_color(t.border)
    .bg(t.input)
    .text_size(TEXT.small)
    .text_color(t.foreground);
}

export function TextBox({ id, state, label, height = 96 }) {
  const t = theme();
  return Textarea.new(state)
    .id(id)
    .w_full()
    .h(height)
    .px(10)
    .py(7)
    .rounded(8)
    .border_1()
    .border_color(t.border)
    .bg(t.input)
    .text_size(TEXT.small)
    .text_color(t.foreground)
    .accessibility_label(label);
}

function MenuBody({ id, width, focus, children, onKey }) {
  const t = theme();
  return v_flex()
    .id(`${id}-menu`)
    .w(width)
    .max_h(300)
    .overflow_y_scrollbar()
    .p(5)
    .gap(1)
    .rounded(7)
    .border_1()
    .border_color(t.border)
    .bg(t.popover)
    .text_color(t.foreground)
    .track_focus(focus)
    .on_key_down(onKey)
    .children(children);
}

// A chooser: a trigger and a popup of `choices`, with arrow keys, Enter and Esc.
// Each choice is {id, label, detail?, disabled?, divided?}. `value` marks the current one.
export function Select({
  id,
  label,
  prefix,
  trigger,
  choices,
  value,
  open,
  index,
  focus,
  triggerFocus,
  width = 200,
  anchor = "top_right",
  accessibilityLabel,
  small = false,
  onOpenChange,
  onMove,
  onChoose,
}) {
  const t = theme();
  const enabled = choices.filter((c) => !c.disabled);
  const button =
    trigger ??
    h_flex()
      .id(`${id}-trigger`)
      .h(small ? 26 : 32)
      .flex_none()
      .px(small ? 8 : 10)
      .gap(6)
      .items_center()
      .rounded(small ? 6 : 8)
      .border_1()
      .border_color(t.border)
      .text_size(TEXT.small)
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .when(Boolean(triggerFocus), (el) =>
        el.track_focus(triggerFocus).on_key_down((event, cx) => {
          if (!["enter", "space", "down", "up"].includes(event.key)) return;
          cx.stop_propagation();
          onOpenChange(!open, cx);
        }),
      )
      .when(Boolean(prefix), (el) => el.child(div().text_color(t.dim).child(prefix)))
      .child(div().flex_1().min_w(0).truncate().child(label))
      .child(Icon("chevron-down", 11).text_color(t.dim));
  const onKey = (event, cx) => {
    if (event.key === "escape") {
      cx.stop_propagation();
      onOpenChange(false, cx);
    } else if ((event.key === "up" || event.key === "down") && enabled.length) {
      cx.stop_propagation();
      onMove((index + (event.key === "down" ? 1 : enabled.length - 1)) % enabled.length, cx);
    } else if (event.key === "enter" && enabled[index]) {
      cx.stop_propagation();
      onChoose(enabled[index], cx);
    }
  };
  const highlighted = enabled[index]?.id;
  const options = choices.flatMap((choice) => [
    ...(choice.divided ? [div().h(1).my(4).flex_none().bg(t.border)] : []),
    v_flex()
      .id(`${id}-option-${choice.id}`)
      .flex_none()
      .min_h(31)
      .px(8)
      .py(5)
      .gap(1)
      .justify_center()
      .rounded(7)
      .text_size(TEXT.tab)
      .text_color(choice.disabled ? t.dim : t.foreground)
      .role("list_box_option")
      .aria_selected(choice.id === value)
      .when(choice.id === highlighted, (el) => el.aria_active_descendant().bg(t.selected))
      .when(!choice.disabled, (el) =>
        el
          .cursor_pointer()
          .hover((s) => s.bg(t.hover))
          .on_click((_e, cx) => onChoose(choice, cx)),
      )
      .child(div().truncate().child(choice.label))
      .when(Boolean(choice.detail), (el) =>
        el.child(div().truncate().text_size(TEXT.caption).text_color(t.dim).child(choice.detail)),
      ),
  ]);
  return Popover.new(id)
    .accessibility_label(accessibilityLabel ?? label)
    .open(open)
    .anchor(anchor)
    .track_focus(focus)
    .on_open_change((value, cx) => onOpenChange(value, cx))
    .trigger(button)
    .when(open, (el) => el.content(MenuBody({ id, width, focus, children: options, onKey })));
}

// A changed file's colour, the same as its letter: green for new, red for gone or in
// conflict, yellow for edited.
export const markColor = (mark, t) =>
  !mark ? null : mark === "A" ? t.ansi2 : mark === "D" || mark === "U" ? t.ansi1 : t.ansi3;

export function StatusLetter(status) {
  const t = theme();
  const color = markColor(status, t);
  return div()
    .w(12)
    .flex_none()
    .text_center()
    .text_size(TEXT.caption)
    .text_color(color)
    .child(status);
}
