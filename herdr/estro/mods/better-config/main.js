// Better Config: every installed mod's settings in one dialog, drawn like
// Herdr's own Settings. Values stay in each mod's mod.json `settings` block,
// where the mod (and any helper beside it) already reads them, and Herdr
// reloads a mod when that file is saved. A copy of what the person changed is
// kept in ~/.config/herdr-mods/better-config/, outside every mod, so values an
// update wiped can be put back.
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, Scrollbar, InputState, Input, Select, Popup, Checkbox } from "gpui-base";
import { appHome, home, exec, readTextFile, writeTextFile, theme, props, closeOverlay, run, window, layout } from "herdr";
import {
  fieldsOf,
  getPath,
  problemWith,
  parseInput,
  showValue,
  isChanged,
  changedValues,
  lostValues,
  editManifest,
  equal,
  modTitle,
  modUse,
  shippedMods,
  installedRows,
  filterInstalled,
  rebind,
} from "./model.js";
import { pickListMods, pickMkdir } from "./shell.js";

const I = (name) => `mods/better-config/icons/${name}.svg`;
const POLL_MS = 3000;
// The Installed page's place in the list; no mod folder can have this name.
const INSTALLED = "*installed";
const USE = { layout: "In this layout", key: "Opens by key" };
const INSTALLED_TABS = { yours: "Yours", herdr: "Herdr's" };

export default class BetterConfig extends View {
  init(_props, cx) {
    this.mods = [];
    this.installed = []; // every mod folder, for the Installed page
    this.keys = null; // keys.json, to tell which mods open by a key
    this.installedTab = "yours";
    // Made here, since Herdr allows making a text box only outside render.
    this.installedSearch = InputState.new({ placeholder: "Search mods" });
    this.installedSearch.on("change", (_e, cx) => cx.notify());
    this.loaded = false;
    this.section = null;
    this.inputs = {}; // "mod:key" → { state, focused }
    this.unticked = new Set();
    this.notes = {}; // "mod:key" → why the typed value wasn't saved
    this.handle = cx.focus_handle();
    this.handle.focus();
    this.menuFocus = cx.focus_handle();
    this.triggerFocus = cx.focus_handle();
    this.openMenu = null; // the dropdown that's open
    this.menuIndex = 0;
    cx.spawn(async (cx) => {
      await this.load();
      cx.notify();
    });
    // Picks up edits made by hand, or by an update, while the dialog is open.
    cx.timer.every(POLL_MS, (cx) =>
      cx.spawn(async (cx) => {
        if (await this.load()) cx.notify();
      }),
    );
  }

  keptFolder() {
    return `${home()}/.config/herdr-mods/better-config`;
  }

  // Every installed mod with settings: described by its mod.schema.json, or set in its mod.json. Returns whether anything changed.
  async load() {
    const { program, args } = pickListMods(`${appHome()}/mods`, window()?.platform);
    const listing = await exec(program, args);
    const names = listing.stdout.split("\n").map((n) => n.replace(/\/$/, "")).filter(Boolean);
    const mods = [];
    const entries = [];
    for (const name of names) {
      const path = `${appHome()}/mods/${name}/mod.json`;
      const raw = await readTextFile(path);
      if (raw === null) {
        entries.push({ name, manifest: null, missing: true });
        continue;
      }
      let manifest = null;
      let error = null;
      try {
        manifest = JSON.parse(raw);
      } catch (e) {
        error = `mod.json isn't valid JSON, so nothing here can be changed until it's fixed: ${e.message}`;
      }
      entries.push({ name, manifest });
      let schema = null;
      try {
        schema = JSON.parse((await readTextFile(`${appHome()}/mods/${name}/mod.schema.json`)) ?? "null");
      } catch {}
      const fields = fieldsOf(schema, manifest?.settings);
      if (manifest && !fields.length) continue;
      if (!manifest && !schema?.properties?.settings && !/"settings"/.test(raw)) continue;
      const keptPath = `${this.keptFolder()}/${name}.json`;
      const keptRaw = await readTextFile(keptPath);
      let kept = null;
      try {
        kept = keptRaw ? JSON.parse(keptRaw) : null;
      } catch {}
      const mod = { name, path, raw, manifest, schema, fields, error, keptPath, keptRaw, kept, lost: {} };
      if (manifest) {
        mod.lost = lostValues(kept, fields, manifest);
        // Nothing lost: the copy follows the file, including edits made by hand.
        if (!Object.keys(mod.lost).length) await this.keep(mod);
      }
      mods.push(mod);
    }
    mods.sort((a, b) => this.titleOf(a).localeCompare(this.titleOf(b)));
    const installed = installedRows(entries, shippedMods(await this.readJson(`${appHome()}/installed.json`)));
    const keys = await this.readJson(`${appHome()}/keys.json`);
    const shown = layout();
    const shape = (list, rows, k, l) => JSON.stringify([list.map((m) => [m.name, m.raw, m.keptRaw]), rows, k, l]);
    const before = shape(this.mods, this.installed, this.keys, this.layout);
    this.mods = mods;
    this.installed = installed;
    this.keys = keys;
    this.layout = shown;
    this.loaded = true;
    if (this.section !== INSTALLED && !mods.some((m) => m.name === this.section)) this.section = mods[0]?.name ?? INSTALLED;
    this.makeInputs();
    return before !== shape(mods, installed, keys, shown);
  }

  // A JSON file, or null when it's missing or unreadable.
  async readJson(path) {
    try {
      return JSON.parse((await readTextFile(path)) ?? "null");
    } catch {
      return null;
    }
  }

  titleOf(mod) {
    return modTitle(mod.name, mod.manifest);
  }

  // Writes the copy of this mod's changed values, when it differs.
  async keep(mod) {
    const next = { version: mod.manifest.version ?? null, values: changedValues(mod.fields, mod.manifest.settings) };
    if (mod.kept && equal(mod.kept, next)) return;
    const text = `${JSON.stringify(next, null, 2)}\n`;
    try {
      if (mod.keptRaw === null) {
        const { program, args } = pickMkdir(this.keptFolder(), window()?.platform);
        await exec(program, args);
      }
      await writeTextFile(mod.keptPath, text, mod.keptRaw);
      mod.kept = next;
      mod.keptRaw = text;
    } catch {}
  }

  // Changes one setting in a mod's mod.json, the way Herdr's Settings changes its own file:
  // only if nobody changed it meanwhile, else read again and redo.
  change(name, edits, cx) {
    cx.spawn(async (cx) => {
      let failed = null;
      for (let attempt = 0; attempt < 3; attempt++) {
        const mod = this.mods.find((m) => m.name === name);
        if (!mod || mod.error) break;
        try {
          let text = mod.raw;
          for (const [key, value] of edits) text = editManifest(text, mod.fields.find((f) => f.key === key) ?? { key }, value);
          await writeTextFile(mod.path, text, mod.raw);
          // The copy follows at once, so a reset never reads as a loss.
          mod.raw = text;
          mod.manifest = JSON.parse(text);
          mod.fields = fieldsOf(mod.schema, mod.manifest.settings);
          await this.keep(mod);
          for (const [key, value] of edits) {
            const field = mod.fields.find((f) => f.key === key);
            if (field?.type === "key") await this.bindKey(name, field, value ?? field.default);
          }
          failed = null;
          break;
        } catch (e) {
          failed = e?.message ?? String(e);
          await this.load();
        }
      }
      if (failed) this.notes[`${name}:*`] = `Couldn't save: ${failed}`;
      else delete this.notes[`${name}:*`];
      await this.load();
      cx.notify();
    });
  }

  // A key setting changes keys.json too: its action moves to the new key. What the key did
  // before is kept in displaced-keys.json beside the copies, and comes back when the action moves off it.
  async bindKey(name, field, key) {
    const path = `${appHome()}/keys.json`;
    const keptPath = `${this.keptFolder()}/displaced-keys.json`;
    const note = `${name}:${field.key}`;
    try {
      const [raw, keptRaw] = await Promise.all([readTextFile(path), readTextFile(keptPath)]);
      const next = rebind(JSON.parse(raw ?? "{}"), JSON.parse(keptRaw ?? "{}"), field.action, key);
      await writeTextFile(path, `${JSON.stringify(next.keys, null, 2)}\n`, raw);
      const kept = `${JSON.stringify(next.displaced, null, 2)}\n`;
      if (kept !== (keptRaw ?? "{}\n")) {
        if (keptRaw === null) {
          const { program, args } = pickMkdir(this.keptFolder(), window()?.platform);
          await exec(program, args);
        }
        await writeTextFile(keptPath, kept, keptRaw);
      }
      delete this.notes[note];
    } catch (e) {
      this.notes[note] = `Saved, but keys.json wasn't changed: ${e?.message ?? e}`;
    }
  }

  // Back to what the mod ships with: its described default, or nothing.
  reset(mod, field, cx) {
    delete this.notes[`${mod.name}:${field.key}`];
    this.change(mod.name, [[field.key, field.default]], cx);
  }

  // Puts back the lost values still ticked; the rest stay as they are now, and the copy
  // forgets them once the write updates it.
  restore(mod, cx) {
    const picked = Object.entries(mod.lost).filter(([key]) => !this.unticked.has(`${mod.name}:${key}`));
    for (const key of Object.keys(mod.lost)) this.unticked.delete(`${mod.name}:${key}`);
    if (picked.length) this.change(mod.name, picked, cx);
    else this.forget(mod, cx);
  }

  // The values aren't wanted back: the copy starts again from the file.
  forget(mod, cx) {
    cx.spawn(async (cx) => {
      mod.kept = null;
      mod.lost = {};
      await this.keep(mod);
      await this.load();
      cx.notify();
    });
  }

  close() {
    const overlay = props()?.overlay;
    if (overlay) closeOverlay(overlay);
  }

  // Pieces, as Herdr's Settings draws them -------------------------------

  heading(t, text) {
    return div().pt(18).pb(2).text_size(12).font_semibold().text_color(t.dim).child(text.toUpperCase());
  }

  button(t, id, label, onClick) {
    return div()
      .id(id)
      .flex_none()
      .px(12)
      .py(5)
      .rounded(7)
      .border_1()
      .border_color(t.border)
      .bg(t.raised)
      .cursor_pointer()
      .text_size(13)
      .text_color(t.foreground)
      .hover((s) => s.bg(t.hover))
      .on_click((_e, cx) => onClick(cx))
      .child(label);
  }

  toggle(t, id, on, onClick) {
    return div()
      .id(id)
      .w(36)
      .h(20)
      .rounded(10)
      .p(2)
      .cursor_pointer()
      .bg(on ? t.accent : t.hover)
      .flex()
      .when(on, (el) => el.justify_end())
      .on_click((_e, cx) => onClick(cx))
      .child(div().w(16).h(16).rounded(8).bg(on ? t.accent_foreground : t.muted));
  }

  segments(t, id, choices, now, onPick) {
    return h_flex()
      .p(2)
      .gap(2)
      .rounded(8)
      .border_1()
      .border_color(t.border)
      .bg(t.background)
      .children(
        Object.entries(choices).map(([value, label]) =>
          div()
            .id(`${id}-${value}`)
            .px(12)
            .py(4)
            .rounded(6)
            .text_size(13)
            .cursor_pointer()
            .when(now === value, (el) => el.bg(t.raised).text_color(t.foreground).border_1().border_color(t.border))
            .when(now !== value, (el) => el.text_color(t.muted).hover((s) => s.text_color(t.foreground)))
            .on_click((_e, cx) => onPick(value, cx))
            .child(label),
        ),
      );
  }

  // A dropdown for a choice with too many options for buttons. Arrows, Enter and Esc work in it.
  dropdown(t, id, label, choices, now, onPick) {
    const entries = Object.entries(choices);
    const open = this.openMenu === id;
    const setOpen = (value, cx) => {
      this.openMenu = value ? id : null;
      this.menuIndex = Math.max(0, entries.findIndex(([v]) => v === now));
      // Opened by a click, the keyboard would stay on the trigger.
      if (value) this.menuFocus.focus();
      else this.handle.focus();
      cx.notify();
    };
    const pick = (value, cx) => {
      setOpen(false, cx);
      if (value !== now) onPick(value, cx);
    };
    const trigger = h_flex()
      .id(`${id}-trigger`)
      .h(28)
      .min_w(140)
      .px(10)
      .gap(6)
      .items_center()
      .rounded(7)
      .border_1()
      .border_color(t.border)
      .bg(t.raised)
      .text_size(13)
      .text_color(t.foreground)
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click((_e, cx) => setOpen(!open, cx))
      .child(div().flex_1().truncate().child(choices[now] ?? String(now ?? "")))
      .child(svg(I("chevron-down")).size(12).text_color(t.dim));
    const menu = v_flex()
      .id(`${id}-menu`)
      .w(200)
      .max_h(300)
      .p(5)
      .gap(1)
      .rounded(7)
      .border_1()
      .border_color(t.border)
      .bg(t.popover)
      .track_focus(this.menuFocus)
      .on_key_down((e, cx) => {
        const k = e.key;
        if (k === "escape") setOpen(false, cx);
        else if (k === "up" || k === "down") {
          this.menuIndex = (this.menuIndex + (k === "down" ? 1 : entries.length - 1)) % entries.length;
          cx.notify();
        } else if (k === "enter" || k === "space") pick(entries[this.menuIndex][0], cx);
        else return;
        cx.stop_propagation();
      })
      .children(
        entries.map(([value, label], i) =>
          h_flex()
            .id(`${id}-option-${value}`)
            .h(30)
            .px(8)
            .gap(8)
            .items_center()
            .rounded(6)
            .text_size(13)
            .text_color(t.foreground)
            .cursor_pointer()
            .role("list_box_option")
            .aria_selected(value === now)
            .when(i === this.menuIndex, (el) => el.aria_active_descendant().bg(t.selected))
            .hover((s) => s.bg(t.hover))
            .on_click((_e, cx) => pick(value, cx))
            .child(div().flex_1().truncate().child(label))
            .when(value === now, (el) => el.child(svg(I("check")).size(12).text_color(t.accent))),
        ),
      );
    // Base owns the open state and moving the keyboard onto the list; the list moves its highlight.
    return Select.new(id)
      .accessibility_label(label)
      .open(open)
      .when(open, (el) => el.track_focus(this.triggerFocus))
      .content_focus_handle(this.menuFocus)
      .on_open_change((value, cx) => setOpen(value, cx))
      .child(Popup.new(`${id}-popup`, trigger).anchor("top_right").when(open, (el) => el.content(menu)));
  }

  // − value +
  stepper(t, id, value, step, onStep) {
    const b = (k, label, by) =>
      div()
        .id(`${id}-${k}`)
        .w(28)
        .h(28)
        .flex()
        .items_center()
        .justify_center()
        .cursor_pointer()
        .text_size(15)
        .text_color(t.muted)
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_click((_e, cx) => onStep(by, cx))
        .child(label);
    return h_flex()
      .items_center()
      .rounded(7)
      .border_1()
      .border_color(t.border)
      .bg(t.raised)
      .overflow_hidden()
      .child(b("minus", "−", -step))
      .child(div().min_w(54).px(6).text_size(13).text_color(t.foreground).flex().justify_center().child(String(value)))
      .child(b("plus", "+", step));
  }

  // Text boxes for the settings typed in. Herdr allows making them only outside render,
  // so they're made here, after each load.
  makeInputs() {
    for (const mod of this.mods) {
      if (!mod.manifest) continue;
      for (const field of mod.fields)
        if (this.usesBox(field, getPath(mod.manifest.settings, field.key))) this.makeInput(mod.name, field);
    }
  }

  usesBox(field, value) {
    const shown = value === undefined ? field.default : value;
    if (field.type === "boolean") return false;
    if (field.type === "choice" && field.choices) return false;
    return !(field.type === "number" && typeof shown === "number");
  }

  makeInput(name, field) {
    const id = `${name}:${field.key}`;
    if (this.inputs[id]) return;
    const value = getPath(this.mods.find((m) => m.name === name)?.manifest?.settings, field.key);
    const state = InputState.new({ placeholder: field.default === undefined ? "" : showValue(field.default) });
    state.set_value(showValue(value));
    const box = (this.inputs[id] = { state, focused: false, shown: showValue(value) });
    // Saves on Enter or when the box loses focus.
    const commit = (cx) => {
      const now = this.mods.find((m) => m.name === name);
      const f = now?.manifest && now.fields.find((x) => x.key === field.key);
      if (!f) return;
      const typed = state.value();
      if (typed === showValue(getPath(now.manifest.settings, f.key))) return;
      const parsed = parseInput(f, typed);
      if (parsed.error) this.notes[id] = parsed.error;
      else {
        delete this.notes[id];
        this.change(name, [[f.key, parsed.value]], cx);
      }
      cx.notify();
    };
    state.on("focus", (_e, cx) => {
      box.focused = true;
      cx.notify();
    });
    state.on("blur", (_e, cx) => {
      box.focused = false;
      commit(cx);
    });
    state.on("submit", (_e, cx) => commit(cx));
  }

  textBox(t, mod, field, value) {
    const id = `${mod.name}:${field.key}`;
    const box = this.inputs[id];
    if (!box) return div().text_size(13).text_color(t.dim).child(showValue(value));
    // Follow the file while the person isn't typing in it.
    if (!box.focused && box.shown !== showValue(value)) {
      box.state.set_value(showValue(value));
      box.shown = showValue(value);
      delete this.notes[id];
    }
    return div()
      .w(field.type === "text" || field.type === "list" ? 240 : 120)
      .h(28)
      .px(8)
      .flex()
      .items_center()
      .rounded(7)
      .border_1()
      .border_color(this.notes[id] ? t.ansi1 : box.focused ? t.accent : t.border)
      .bg(t.background)
      .text_size(13)
      .child(Input.new(box.state).h(26).w_full().text_color(t.foreground));
  }

  control(t, mod, field, value) {
    const id = `bc-${mod.name}-${field.key}`;
    const set = (v, cx) => this.change(mod.name, [[field.key, v]], cx);
    const shown = value === undefined ? field.default : value;
    if (field.type === "boolean") return this.toggle(t, id, shown === true, (cx) => set(!(shown === true), cx));
    if (field.type === "choice" && field.choices)
      return Object.keys(field.choices).length <= 4
        ? this.segments(t, id, field.choices, shown, (v, cx) => set(v, cx))
        : this.dropdown(t, id, field.title, field.choices, shown, (v, cx) => set(v, cx));
    if (field.type === "number" && typeof shown === "number") {
      const clamp = (v) => Math.min(field.max ?? Infinity, Math.max(field.min ?? -Infinity, v));
      return h_flex()
        .gap(6)
        .items_center()
        .child(this.stepper(t, id, shown, field.step, (by, cx) => set(clamp(shown + by), cx)))
        .when(Boolean(field.unit), (el) => el.child(div().text_size(12.5).text_color(t.dim).child(field.unit)));
    }
    return this.textBox(t, mod, field, value);
  }

  // One setting: what it is on the left, the control on the right, any problem under it.
  row(t, mod, field) {
    const value = getPath(mod.manifest.settings, field.key);
    const problem = this.notes[`${mod.name}:${field.key}`] ?? problemWith(field, value);
    const changed = isChanged(field, value);
    const about = field.description;
    return h_flex()
      .w_full()
      .gap(16)
      .py(12)
      .items_center()
      .border_b(1)
      .border_color(t.border)
      .child(
        v_flex()
          .flex_1()
          .min_w(0)
          .gap(3)
          .child(
            h_flex()
              .gap(8)
              .items_center()
              .child(div().text_size(14).text_color(t.foreground).child(field.title))
              .when(changed, (el) => el.child(div().w(6).h(6).rounded(3).bg(t.accent))),
          )
          .when(Boolean(about), (el) =>
            el.child(div().text_size(12.5).line_height("18px").text_color(t.dim).child(about)),
          )
          .child(div().text_size(11.5).text_color(t.dim).font_family("JetBrains Mono").child(field.key))
          .when(Boolean(problem), (el) => el.child(div().text_size(12.5).text_color(t.ansi1).child(problem))),
      )
      .when(changed, (el) =>
        el.child(
          div()
            .id(`bc-reset-${mod.name}-${field.key}`)
            .flex_none()
            .px(6)
            .py(3)
            .rounded(5)
            .text_size(12)
            .text_color(t.dim)
            .cursor_pointer()
            .hover((s) => s.bg(t.hover).text_color(t.foreground))
            .tooltip(`Back to ${showValue(field.default) || "the default"}`)
            .on_click((_e, cx) => this.reset(mod, field, cx))
            .child("Reset"),
        ),
      )
      .child(div().flex_none().child(this.control(t, mod, field, value)));
  }

  // When an update put the shipped values back over the person's own.
  // What an update (or anything else) put back over the person's values: each one, yours then now.
  lostBanner(t, mod) {
    const keys = Object.keys(mod.lost);
    const updated = mod.kept?.version && mod.manifest?.version && mod.kept.version !== mod.manifest.version;
    const ticked = keys.filter((key) => !this.unticked.has(`${mod.name}:${key}`)).length;
    const restoreLabel =
      ticked === keys.length ? "Restore mine" : ticked === 0 ? "Keep the new values" : `Restore ${ticked}, keep ${keys.length - ticked}`;
    const which = keys.length === 1 ? "one of your settings" : `${keys.length} of your settings`;
    const shown = (value, field) =>
      value === undefined || showValue(value) === "" ? "empty" : (field?.choices?.[value] ?? showValue(value));
    return v_flex()
      .mt(14)
      .p(12)
      .gap(10)
      .rounded(8)
      .border_1()
      .border_color(t.border)
      .bg(t.raised)
      .child(
        div()
          .text_size(13)
          .text_color(t.foreground)
          .child(
            updated
              ? `Updating ${this.titleOf(mod)} from ${mod.kept.version} to ${mod.manifest.version} reset ${which}:`
              : `Something outside Better Config put back ${which}:`,
          ),
      )
      .child(
        v_flex()
          .gap(4)
          .children(
            keys.map((key) => {
              const field = mod.fields.find((f) => f.key === key);
              const now = getPath(mod.manifest?.settings, key) ?? field?.default;
              const id = `${mod.name}:${key}`;
              const on = !this.unticked.has(id);
              return Checkbox.new(`bc-pick-${id}`)
                .checked(on)
                .on_change((checked, cx) => {
                  if (checked) this.unticked.delete(id);
                  else this.unticked.add(id);
                  cx.notify();
                })
                .accessibility_label(`Restore ${field?.title ?? key}`)
                .flex()
                .gap(8)
                .items_center()
                .cursor_pointer()
                .text_size(12.5)
                .child(
                  div()
                    .size(15)
                    .flex_none()
                    .flex()
                    .items_center()
                    .justify_center()
                    .rounded(4)
                    .border_1()
                    .border_color(on ? t.accent : t.border)
                    .bg(on ? t.accent : t.background)
                    .when(on, (el) => el.child(svg(I("check")).size(11).text_color(t.accent_foreground))),
                )
                .child(div().w(150).flex_none().truncate().text_color(t.muted).child(field?.title ?? key))
                .child(div().font_family("JetBrains Mono").text_color(t.foreground).child(shown(mod.lost[key], field)))
                .child(div().text_color(t.dim).child("→"))
                .child(div().font_family("JetBrains Mono").text_color(t.dim).child(`${shown(now, field)}${getPath(mod.manifest?.settings, key) === undefined ? " (default)" : ""}`));
            }),
          ),
      )
      .child(
        h_flex().child(this.button(t, `bc-restore-${mod.name}`, restoreLabel, (cx) => this.restore(mod, cx))),
      );
  }

  // Every mod folder: the person's own, then Herdr's, with its version, where it's used, and
  // a way to its settings.
  installedPage(t) {
    const shown = layout();
    const group = (rows) =>
      v_flex()
        .pt(6)
        .children(
          rows.map((row) => {
            const use = modUse(row.name, shown, this.keys);
            const settings = this.mods.some((m) => m.name === row.name);
            return h_flex()
              .id(`bc-installed-${row.name}`)
              .w_full()
              .gap(16)
              .py(10)
              .items_center()
              .border_b(1)
              .border_color(t.border)
              .child(
                v_flex()
                  .flex_1()
                  .min_w(0)
                  .gap(2)
                  .child(div().text_size(14).text_color(t.foreground).truncate().child(row.title))
                  .child(
                    div()
                      .text_size(11.5)
                      .text_color(t.dim)
                      .font_family("JetBrains Mono")
                      .child(row.missing ? `${row.name} · no mod.json` : row.name),
                  ),
              )
              .child(div().flex_none().w(60).text_size(12.5).text_color(t.dim).child(row.version ?? ""))
              .child(
                div()
                  .flex_none()
                  .w(110)
                  .text_size(12.5)
                  .text_color(use ? t.muted : t.dim)
                  .child(USE[use] ?? "Not used here"),
              )
              .child(
                div()
                  .flex_none()
                  .w(80)
                  .flex()
                  .justify_end()
                  .when(settings, (el) =>
                    el.child(
                      this.button(t, `bc-installed-settings-${row.name}`, "Settings", (cx) => {
                        this.section = row.name;
                        this.handle.focus();
                        cx.notify();
                      }),
                    ),
                  ),
              );
          }),
        );
    const rows = filterInstalled(this.installed, this.installedTab, this.installedSearch.value());
    const count = (tab) => this.installed.filter((r) => r.herdr === (tab === "herdr")).length;
    const tabs = Object.fromEntries(Object.entries(INSTALLED_TABS).map(([id, label]) => [id, `${label} ${count(id)}`]));
    return v_flex()
      .child(
        h_flex()
          .h(30)
          .gap(10)
          .items_center()
          .child(div().text_size(18).font_semibold().text_color(t.foreground).child("Installed mods"))
          .child(div().text_size(12.5).text_color(t.dim).child(String(this.installed.length))),
      )
      .child(
        div()
          .pt(4)
          .text_size(12.5)
          .text_color(t.dim)
          .child(
            this.installedTab === "herdr"
              ? "Herdr's own mods, which it replaces on every start. Where each is used is for the layout on screen now."
              : "Every mod you added to mods/. Where each is used is for the layout on screen now.",
          ),
      )
      .child(
        h_flex()
          .pt(14)
          .pb(4)
          .gap(12)
          .items_center()
          .child(
            this.segments(t, "bc-installed-tab", tabs, this.installedTab, (tab, cx) => {
              this.installedTab = tab;
              cx.notify();
            }),
          )
          .child(div().flex_1())
          .child(
            div()
              .w(220)
              .h(28)
              .px(8)
              .flex()
              .items_center()
              .rounded(7)
              .border_1()
              .border_color(t.border)
              .bg(t.background)
              .text_size(13)
              .child(Input.new(this.installedSearch).h(26).w_full().text_color(t.foreground)),
          ),
      )
      .when(rows.length > 0, (el) => el.child(group(rows)))
      .when(!rows.length, (el) =>
        el.child(
          div()
            .py(14)
            .text_size(13)
            .text_color(t.dim)
            .child(this.installedSearch.value().trim() ? "No mods match your search." : "No mods here."),
        ),
      );
  }

  page(t, mod) {
    if (this.section === INSTALLED) return this.installedPage(t);
    const fields = mod.manifest ? mod.fields : [];
    const changed = fields.filter((f) => isChanged(f, getPath(mod.manifest.settings, f.key)));
    // Grouped by the first part of the key; one-part keys go first, with no heading.
    const groups = [];
    for (const field of fields) {
      const name = field.key.includes(".") ? field.key.split(".")[0] : "";
      let group = groups.find((g) => g.name === name);
      if (!group) groups.push((group = { name, fields: [] }));
      group.fields.push(field);
    }
    groups.sort((a, b) => (a.name === "" ? -1 : b.name === "" ? 1 : 0));
    const saveNote = this.notes[`${mod.name}:*`];
    return v_flex()
      .child(
        h_flex()
          .h(30)
          .gap(10)
          .items_center()
          .child(div().text_size(18).font_semibold().text_color(t.foreground).child(this.titleOf(mod)))
          .when(Boolean(mod.manifest?.version), (el) =>
            el.child(div().text_size(12.5).text_color(t.dim).child(mod.manifest.version)),
          )
          .child(div().flex_1())
          .when(changed.length > 0, (el) =>
            el.child(
              this.button(t, `bc-reset-all-${mod.name}`, "Reset all", (cx) =>
                this.change(mod.name, changed.map((f) => [f.key, f.default]), cx),
              ),
            ),
          ),
      )
      .child(
        div()
          .pt(4)
          .text_size(12.5)
          .text_color(t.dim)
          .child(`Saved to mods/${mod.name}/mod.json, which the mod reloads at once.`),
      )
      .when(Boolean(mod.error), (el) => el.child(div().pt(14).text_size(13).text_color(t.ansi1).child(mod.error)))
      .when(Boolean(saveNote), (el) => el.child(div().pt(14).text_size(13).text_color(t.ansi1).child(saveNote)))
      .when(Object.keys(mod.lost).length > 0, (el) => el.child(this.lostBanner(t, mod)))
      .children(
        groups.map((g) =>
          v_flex()
            .when(Boolean(g.name), (el) => el.child(this.heading(t, g.name.replaceAll("_", " "))))
            .when(!g.name, (el) => el.pt(10))
            .children(g.fields.map((f) => this.row(t, mod, f))),
        ),
      );
  }

  nav(t) {
    return v_flex()
      .flex_none()
      .w(190)
      .h_full()
      .p(10)
      .gap(2)
      .border_r(1)
      .border_color(t.border)
      .child(div().px(10).pt(6).pb(12).text_size(16).font_semibold().text_color(t.foreground).child("Mod settings"))
      .child(this.navItem(t, INSTALLED, "Installed mods", false))
      .child(div().mx(10).my(6).h(1).bg(t.border))
      .child(
        div()
          .id("bc-nav")
          .flex_1()
          .min_h(0)
          .overflow_y_scroll()
          .child(
            v_flex()
              .gap(2)
              .children(
                this.mods.map((mod) =>
                  this.navItem(t, mod.name, this.titleOf(mod), mod.error || Object.keys(mod.lost).length > 0),
                ),
              ),
          ),
      )
      .child(this.button(t, "bc-herdr", "Herdr settings", () => {
        this.close();
        run("app.settings");
      }));
  }

  // One entry in the list on the left: a mod's settings, or the Installed page.
  navItem(t, section, label, attention) {
    const on = section === this.section;
    return h_flex()
      .id(section === INSTALLED ? "bc-s-installed" : `bc-s-${section}`)
      .gap(10)
      .px(10)
      .py(7)
      .items_center()
      .rounded(7)
      .cursor_pointer()
      .bg(on ? t.raised : "#00000000")
      .hover((s) => s.bg(t.raised))
      .on_click((_e, cx) => {
        this.section = section;
        this.handle.focus();
        cx.notify();
      })
      .child(div().flex_1().min_w(0).truncate().text_size(13.5).text_color(on ? t.foreground : t.muted).child(label))
      .when(Boolean(attention), (el) => el.child(div().w(7).h(7).rounded(4).bg(t.ansi1)));
  }

  render(cx) {
    const t = theme();
    const mod = this.mods.find((m) => m.name === this.section);
    return h_flex()
      .id("better-config")
      .track_focus(this.handle)
      .size_full()
      .min_h(0)
      .items_start()
      .bg(t.popover)
      .on_key_down((e, cx) => {
        if (e.key !== "escape") return;
        cx.stop_propagation();
        this.close();
      })
      .child(this.nav(t))
      .child(
        div()
          .relative()
          .flex_1()
          .min_w(0)
          .h_full()
          .child(
            div()
              .id("bc-body")
              .size_full()
              .overflow_y_scroll()
              .child(
                div()
                  .px(28)
                  .py(22)
                  .child(this.loaded ? this.page(t, mod) : div().text_size(13).text_color(t.dim).child("Loading…")),
              ),
          )
          .child(Scrollbar.vertical("bc-body").mode("always").absolute().inset_0()),
      );
  }
}
