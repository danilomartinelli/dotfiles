// Better Search: one popup that finds anything. With nothing typed, every open tab on every
// machine, the ones that need you first, opened on the tab you were in before. A leading @
// narrows it to agents, > to Herdr's commands, / to files in this space, ~ to spaces, ? to
// what agents printed, # to pull requests, $ to Linear issues. Enter goes there or runs it;
// Shift+Enter peeks at an agent; Cmd+Enter hands an agent a message, or a file; Tab shows all
// of a section. Esc goes back, then closes.
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, TextareaState, Textarea } from "gpui-base";
import {
  agents, appHome, closeOverlay, commands, exec, focused, hc, keys, layout, layouts, panes, props,
  readTextFile, run, setShared, shared, spaces, terminals, theme, themes, window as win,
} from "herdr";
import { loadSettings } from "./settings.js";
import { ago, askOf, commandEntries, drill, githubRepo, message, PREFIXES, previous, reveal, search, visit } from "./model.js";

// `key` is bound in keys.json by Better Config when it changes; the popup never reads it.
const DEFAULT_SETTINGS = { key: "cmd-alt-p", files: { limit: 20000 } };
const RECENT = "better-search.recent";
const VIEWERS = "better-files.viewers";
// Tabs you were in, newest first.
// shortcut: only tabs you were in when Better Search opened, or picked in it; Herdr keeps no history.
const VISITS = "better-search.visits";
// History lines read above each agent's screen for " searches.
const OUTPUT_LINES = 2000;
// # asks GitHub and Linear once typing pauses this long.
const WORK_PAUSE_MS = 400;
const SHOWN = 10;
const ROW_H = 32;
const HEAD_H = 26;
const LIST_H = SHOWN * ROW_H;
// The chips under the search box, one per prefix.
const CHIPS = Object.entries(PREFIXES).map(([p, kind]) => [p, kind === "prs" ? "PRs" : kind]);

const exists = async (mod) => Boolean(await readTextFile(`${appHome()}/mods/${mod}/mod.json`).catch(() => null));

export default class BetterSearch extends View {
  init(_props, cx) {
    this.text = "";
    this.at = null;
    this.scroll = 0;
    this.files = null;
    this.problem = null;
    this.compose = null; // { agent, name, file? }: the input holds a message for that agent.
    this.attach = null; // { path, rel, root, on }: choosing an agent to hand this file to.
    this.machines = [];
    this.asks = {}; // { address: question } for blocked agents, read from their screens.
    this.output = null; // { address: text } once " is typed.
    const here = focused()?.tab ?? null;
    setShared(VISITS, visit(shared(VISITS), here));
    const tabs = new Set(spaces().flatMap((s) => s.tabs.map((t) => t.id)));
    this.last = previous(shared(VISITS), here, (id) => tabs.has(id));
    this.has = { files: false, config: false, pr: false, issue: false };
    this.prs = null; // # results: null while asked, [...], or { error }.
    this.issues = null;
    this.handle = cx.focus_handle();
    this.input = InputState.new({ placeholder: "Search tabs, agents, files and commands" });
    this.input.on("change", (_e, cx) => {
      this.text = this.input.value();
      this.at = this.firstPick();
      this.typed(cx);
      cx.notify();
    });
    // Submit events carry the keys flat: `shift`, and `secondary` for Cmd.
    this.input.on("submit", (e, cx) => this.submit({ shift: e.shift, platform: e.secondary }, cx));
    // The message to an agent can run to several lines: Enter adds one, Cmd+Enter sends.
    this.note = TextareaState.new({ placeholder: "Message" });
    this.note.set_auto_grow(3, 10);
    this.note.on("submit", (e, cx) => e.secondary && this.send(cx));
    this.input.focus();
    cx.timer.after(600, () => this.input.focus());
    cx.spawn(async (cx) => {
      const [config, files] = await Promise.all(["better-config", "better-files"].map(exists));
      // # needs the panels' helpers, which their installers build.
      const built = async (path) => (await exec("test", ["-x", `${appHome()}/mods/${path}`]).catch(() => null))?.code === 0;
      // Branch Issue 3 asks Linear and GitHub through `herdr-issue`; Branch Issue 2 only Linear.
      const [pr, v3, v2] = await Promise.all([built("branch-pr/bin/herdr-pr"), built("branch-issue/bin/herdr-issue"), built("branch-issue/bin/herdr-linear")]);
      const issue = v3 ? "herdr-issue" : v2 ? "herdr-linear" : false;
      this.has = { config, files, pr, issue };
      try {
        const r = await hc(["machine", "ls", "--json"]);
        if (r.code === 0) this.machines = (JSON.parse(r.stdout).machines ?? []).filter((m) => m.state === "connected" && !m.temporary).map((m) => m.name);
      } catch {}
      cx.notify();
    });
    cx.spawn(async (cx) => {
      const blocked = agents().filter((a) => a.status === "blocked");
      const screens = await Promise.all(blocked.map((a) => hc(["read", a.address]).catch(() => null)));
      blocked.forEach((a, i) => {
        const ask = screens[i]?.code === 0 ? askOf(screens[i].stdout) : null;
        if (ask) this.asks[a.address] = ask;
      });
      cx.notify();
    });
    cx.spawn(async (cx) => {
      const { settings, problems } = await loadSettings("better-search", DEFAULT_SETTINGS);
      for (const p of problems) console.warn(`better-search mod.json settings: ${p}`);
      await this.readFiles(settings.files.limit);
      cx.notify();
    });
  }

  // Files in this space: its repository's tracked and untracked files, without ignored ones.
  // shortcut: a folder outside git lists no files; walk it if people ask for that.
  async readFiles(limit) {
    const space = spaces().find((s) => s.active);
    const here = focused();
    const cwd = (here?.space === space?.id && here?.cwd) || space?.folder || null;
    const on = space?.machine ?? null;
    try {
      const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd: cwd || undefined, on });
      if (top.code !== 0) throw new Error("This space isn't in a git repository.");
      const root = top.stdout.trim();
      const ls = await exec("git", ["ls-files", "--cached", "--others", "--exclude-standard"], { cwd: root, on });
      if (ls.code !== 0) throw new Error(ls.stderr.trim() || "git ls-files failed.");
      this.root = { root, on };
      this.files = [...new Set(ls.stdout.split("\n").filter(Boolean))].slice(0, Math.max(1, limit));
    } catch (e) {
      this.files = [];
      this.problem = e.message;
    }
  }

  // What a prefix reads once it's typed, however it got there.
  typed(cx) {
    if (this.text[0] === "?" && !this.output) this.readOutput(cx);
    if (this.text[0] === "#") this.askWork("prs", cx);
    if (this.text[0] === "$") this.askWork("issues", cx);
  }

  // Every agent's screen and recent history, read once, for " searches.
  readOutput(cx) {
    this.output = {};
    this.outputReading = true;
    cx.spawn(async (cx) => {
      const all = agents();
      const reads = await Promise.all(all.map((a) => hc(["read", a.address, "--lines", String(OUTPUT_LINES)]).catch(() => null)));
      all.forEach((a, i) => reads[i]?.code === 0 && (this.output[a.address] = reads[i].stdout));
      this.outputReading = false;
      this.at = this.firstPick();
      cx.notify();
    });
  }

  // # and $ search through Branch PR's and Branch Issue's own helpers, so their GitHub login
  // and Linear key are the ones used. Open ones while nothing's typed; any state for a search.
  askWork(kind, cx) {
    const token = (this.workToken = (this.workToken ?? 0) + 1);
    this[kind] = null;
    cx.timer.after(WORK_PAUSE_MS, (cx) => {
      if (token !== this.workToken) return;
      const q = this.text.slice(1).trim();
      const ask = async (mod, bin, request) => {
        const r = await exec(`${appHome()}/mods/${mod}/bin/${bin}`, [JSON.stringify(request)], { cwd: this.root?.on ? undefined : this.root?.root });
        let data;
        try {
          data = JSON.parse(r.stdout);
        } catch {
          throw new Error(r.stderr.trim() || `${mod} didn't answer`);
        }
        if (r.code !== 0 || data.error) throw new Error(data.error || r.stderr.trim() || `${mod} failed`);
        return data.items ?? [];
      };
      const fill = (key, read) => cx.spawn(async (cx) => {
        let got;
        try {
          got = await read();
        } catch (e) {
          got = { error: e.message };
        }
        if (token !== this.workToken) return;
        this[key] = got;
        if (this.rows()[this.at]?.kind === "head" || !this.rows()[this.at]) this.at = this.firstPick();
        cx.notify();
      });
      if (kind === "prs" && this.has.pr) fill("prs", async () => {
        const repo = await this.githubRepo();
        if (!repo) throw new Error("no GitHub remote here");
        const { settings } = await loadSettings("branch-pr", { tools: { github: "gh" } });
        return ask("branch-pr", "herdr-pr", { action: "list", repo, tab: "all", state: q ? "all" : "open", search: q, cursors: {}, pageSize: 20, tools: settings.tools });
      });
      const linear = { action: "list", scope: "all", state: q ? "all" : "active", team: "", search: q, cursor: "" };
      if (kind === "issues" && this.has.issue === "herdr-linear") fill("issues", () => ask("branch-issue", "herdr-linear", linear));
      // Both trackers at once; one that isn't set up here just adds nothing.
      if (kind === "issues" && this.has.issue === "herdr-issue") fill("issues", async () => {
        const repo = await this.githubRepo();
        const tagged = (source, request) => ask("branch-issue", "herdr-issue", { source, ...request }).then((items) => items.map((i) => ({ ...i, source })));
        const got = await Promise.allSettled([
          repo ? tagged("github", { action: "list", repo, scope: "all", state: q ? "all" : "open", milestone: "", search: q }) : Promise.resolve([]),
          tagged("linear", linear),
        ]);
        if (got.every((g) => g.status === "rejected")) throw got[1].reason;
        return got.flatMap((g) => (g.status === "fulfilled" ? g.value : []));
      });
    });
  }

  // owner/name of this space's GitHub repository, from its upstream or origin remote.
  // shortcut: Branch PR also follows the branch's tracking remote; add that if a fork misses.
  async githubRepo() {
    if (this.repo !== undefined) return this.repo;
    const space = spaces().find((s) => s.active);
    const cwd = this.root?.root ?? space?.folder;
    const on = this.root?.on ?? space?.machine ?? null;
    for (const name of ["upstream", "origin"]) {
      const r = await exec("git", ["remote", "get-url", name], { cwd: cwd || undefined, on }).catch(() => null);
      const repo = r?.code === 0 ? githubRepo(r.stdout) : null;
      if (repo) return (this.repo = repo);
    }
    return (this.repo = null);
  }

  // Shows a PR or issue in its panel: the panel opens it when it sees the ask in shared state.
  // Without the panel in this layout, it opens in the browser.
  openWork(r, cx) {
    const mod = r.kind === "pr" ? "branch-pr" : "branch-issue";
    const steps = reveal(layout(), mod);
    if (!steps) return r.url && cx.open_url(r.url);
    const space = spaces().find((s) => s.active)?.id;
    // `identifier` for Branch Issue 2 (Linear only), `ref` for Branch Issue 3.
    setShared(`${mod}.open`, r.kind === "pr" ? { space, number: r.number, repo: r.repo ?? this.repo ?? null, at: Date.now() } : { space, identifier: r.identifier, ref: r.ref, at: Date.now() });
    for (const [name, args] of steps) run(name, args);
  }

  data() {
    const live = terminals().filter((x) => x.state === "live");
    const teamOf = (mine) => {
      let n = 0;
      const walk = (a) => live.filter((x) => x.parent === a).forEach((k) => (n++, walk(k.address)));
      mine.forEach((a) => walk(a.address));
      return n;
    };
    if (this.entriesFor !== this.has.config) this.entries = null;
    this.entriesFor = this.has.config;
    this.entries ??= commandEntries({
      commands: commands(),
      layouts: layouts(),
      themes: themes().map((t) => t.name),
      keys: keys(),
      mac: win()?.platform === "macos",
      modSettings: this.has.config,
    });
    return {
      spaces: spaces(), agents: agents(), machines: this.machines, teamOf, commands: this.entries, recent: shared(RECENT) ?? [],
      files: this.files, asks: this.asks, last: this.last, output: this.output ?? {}, prs: this.prs, issues: this.issues,
    };
  }

  rows() {
    return search(this.data(), this.text);
  }

  firstPick() {
    return Math.max(0, this.rows().findIndex((r) => r.kind !== "head"));
  }

  close() {
    closeOverlay(props().overlay);
  }

  setText(text) {
    this.input.set_value(text);
    this.text = text;
    this.at = this.firstPick();
    this.input.focus();
  }

  back(cx) {
    if (!this.compose && !this.attach) return this.close();
    const wasAttach = this.compose?.file && this.attach;
    this.compose = null;
    this.error = null;
    if (!wasAttach) this.attach = null;
    this.setText(wasAttach ? "@" : "");
    cx.notify();
  }

  submit(mods, cx) {
    if (this.compose) return this.send(cx);
    const rows = this.rows();
    this.go(rows[this.at], mods, cx);
  }

  startCompose(agent, name, cx) {
    this.compose = { agent, name, file: this.attach?.path ?? null, rel: this.attach?.rel ?? null };
    this.note.set_value("");
    this.note.focus();
    cx.notify();
  }

  go(r, mods, cx) {
    if (!r || r.kind === "head") return;
    const peek = mods.shift && r.agent;
    if (mods.platform && r.url && (r.kind === "pr" || r.kind === "issue")) {
      this.close();
      return cx.open_url(r.url);
    }
    const hand = (mods.platform || this.attach) && r.agent;
    if (hand) return this.startCompose(r.agent, r.title, cx);
    if (r.kind === "file" && mods.platform) {
      this.attach = { ...this.root, path: `${this.root.root}/${r.path}`, rel: r.path };
      this.setText("@");
      return cx.notify();
    }
    this.close();
    if (peek) return run("terminal.peek", { terminal: r.agent });
    if (r.kind === "tab") {
      setShared(VISITS, visit(shared(VISITS), r.id));
      run("tab.select", { id: r.id });
    }
    else if (r.kind === "agent" || r.kind === "output") run("agent.focus", { terminal: r.agent });
    else if (r.kind === "space") run("space.select", { id: r.id });
    else if (r.kind === "new-space") run("space.new", { machine: r.machine ?? "" });
    else if (r.kind === "new-tab") run("tab.new");
    else if (r.kind === "file") this.openFile(r.path);
    else if (r.kind === "pr" || r.kind === "issue") this.openWork(r, cx);
    else if (r.kind === "command") {
      setShared(RECENT, [r.id, ...(shared(RECENT) ?? []).filter((id) => id !== r.id)].slice(0, 20));
      run(r.name, r.args);
    }
  }

  // Opens a file the way Better Files does: its tab if it's open, else a kept tab of its own,
  // registered so Better Files' sidebar and menus know it.
  openFile(rel) {
    const space = spaces().find((s) => s.active)?.id;
    const file = { path: `${this.root.root}/${rel}`, root: this.root.root, on: this.root.on };
    if (!space) return;
    if (!this.has.files) return run("terminal.open", { argv: ["less", file.path], folder: file.root });
    const entries = shared(VIEWERS) ?? {};
    const open = Object.values(entries).find((v) => v.space === space && v.file?.path === file.path && v.tab && panes().some((p) => p.tab === v.tab && p.mod === "better-files"));
    if (open) return run("tab.select", { id: open.tab });
    const id = `v${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
    const others = panes().filter((p) => p.mod === "better-files").map((p) => p.tab);
    setShared(VIEWERS, { ...entries, [id]: { space, file, preview: false, tab: null, others, at: Date.now() } });
    run("tab.new", { space, name: rel.split("/").pop(), mod: "better-files", props: { mode: "viewer", viewer: id, space, file } });
  }

  send(cx) {
    const text = this.note.value().trim();
    if (!text || this.sending) return;
    this.sending = true;
    this.error = null;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const r = await hc(["send", this.compose.agent, message(text, this.compose.file)]);
        if (r.code !== 0) throw new Error(r.stderr.trim() || "The message didn't reach the agent.");
        this.close();
      } catch (e) {
        this.error = e.message; // The box stays open, so nothing typed is lost.
      } finally {
        this.sending = false;
        cx.notify();
      }
    });
  }

  glyph(t, st) {
    if (st === "working") return svg("mods/workspace-chrome/spinner.svg").size(12).flex_none().text_color(t.working).spin(900);
    return div().w(12).flex_none().text_color(t[st] ?? t.dim).child(st === "idle" ? "○" : st ? "●" : "·");
  }

  title(t, text, hits, strong) {
    const base = strong ? t.foreground : t.muted;
    if (!hits?.length) return div().truncate().text_color(base).child(text);
    const parts = [];
    [...text].forEach((ch, i) => {
      const lit = hits.includes(i);
      if (parts.length && parts[parts.length - 1][1] === lit) parts[parts.length - 1][0] += ch;
      else parts.push([ch, lit]);
    });
    return h_flex().min_w(0).overflow_hidden().children(parts.map(([s, lit]) => div().flex_none().text_color(lit ? t.accent : base).when(lit, (d) => d.font_semibold()).child(s.replace(/ /g, " "))));
  }

  key(t, k) {
    const parts = k.endsWith("--") ? [...k.slice(0, -2).split("-"), "-"] : k.split("-");
    return h_flex().gap(3).flex_none().children(parts.map((p) => div().px(5).rounded(4).border_1().border_color(t.border).bg(t.raised).text_size(11).text_color(t.dim).child(p)));
  }

  row(t, r, i, on) {
    if (r.kind === "head") {
      return h_flex().px(14).pb(4).gap(6).items_end().text_size(11).font_semibold().text_color(t.dim)
        .child(r.title)
        .when(Boolean(r.machine), (el) => el.child(div().font_normal().child(`on ${r.machine}`)))
        .when(Boolean(r.more), (el) => el.child(div().font_normal().child(r.more)));
    }
    const plain = r.kind === "new-tab" || r.kind === "new-space";
    const since = ago(r.since, Date.now());
    // Tabs say only what needs you; agents (`spell`) say every state.
    const words = { blocked: "needs you", done: "finished", working: "working", idle: "idle" };
    const state = r.status === "blocked" || r.status === "done" || (r.spell && r.status) ? [words[r.status], t[r.status] ?? t.dim] : null;
    const timed = since && (r.status === "blocked" || r.status === "done") && r.kind !== "output";
    // A PR's or issue's own state: finished ones in `done`, dropped ones dim, the rest at work.
    const tone = !r.state ? null : /merged|done|complete/i.test(r.state) ? t.done : /closed|cancel|duplicate|draft|backlog/i.test(r.state) ? t.dim : t.working;
    return h_flex()
      .id(`bs-${i}`)
      .mx(6)
      .px(10)
      .gap(10)
      .items_center()
      .rounded(7)
      .cursor_pointer()
      .text_size(12.8)
      .when(on, (el) => el.bg(t.selected))
      .hover((s) => s.bg(t.hover))
      .on_click((e, cx) => this.go(r, e.modifiers ?? {}, cx))
      .child(plain ? div().w(12).flex_none().text_color(t.muted).child("+") : r.kind === "command" || r.kind === "file" ? div().w(12).flex_none() : this.glyph(t, r.status))
      .child(div().flex_shrink_1().min_w(0).child(this.title(t, r.title, r.hits, !plain && (on || r.kind !== "command"))))
      // What runs in it, or what its agent asks, right after the name; the rest of the row is space.
      .child(div().flex_1().min_w(0).truncate().text_size(11.5).text_color(r.ask ? t.muted : t.dim).child(r.sub ?? ""))
      .when(Boolean(r.last), (el) => el.child(div().flex_none().text_size(11).text_color(t.dim).child("last")))
      .when(Boolean(state), (el) => el.child(div().flex_none().text_size(11).text_color(state[1]).child(timed ? `${state[0]} · ${since}` : state[0])))
      .when(Boolean(tone), (el) => el.child(div().flex_none().text_size(11).text_color(tone).child(r.state)))
      .when(Boolean(r.detail), (el) => el.child(div().flex_none().max_w(240).truncate().text_size(11.5).text_color(t.dim).child(r.detail)))
      .when(Boolean(r.key), (el) => el.child(this.key(t, r.key)));
  }

  list(t, rows) {
    // As Herdr's palette: each row at a fixed y, placed by its edges so rounding can't drift,
    // and scrolled only as far as keeps the selected row (and the title above it) in view.
    const tops = [];
    let y = 0;
    for (const r of rows) {
      tops.push(y);
      y += r.kind === "head" ? HEAD_H : ROW_H;
    }
    const total = y;
    const fixed = total > LIST_H;
    this.maxScroll = Math.max(0, total - LIST_H);
    const h = (i) => (rows[i].kind === "head" ? HEAD_H : ROW_H);
    if (rows[this.at]) {
      const from = this.at > 0 && rows[this.at - 1].kind === "head" ? tops[this.at - 1] : tops[this.at];
      if (from < this.scroll) this.scroll = from;
      if (tops[this.at] + ROW_H > this.scroll + LIST_H) this.scroll = tops[this.at] + ROW_H - LIST_H;
    }
    this.scroll = Math.max(0, Math.min(this.scroll, this.maxScroll));
    const place = (el, i) =>
      fixed ? el.absolute().left(0).right(0).top(tops[i] - this.scroll).bottom(LIST_H - (tops[i] + h(i) - this.scroll)) : el.flex_none().h(h(i));
    const visible = (i) => !fixed || (tops[i] + h(i) > this.scroll && tops[i] < this.scroll + LIST_H);
    const items = rows.map((r, i) => (visible(i) ? place(this.row(t, r, i, i === this.at), i) : null)).filter(Boolean);
    return div()
      .id("bs-rows")
      .relative()
      .when(fixed, (el) => el.h(LIST_H).overflow_hidden())
      .on_scroll_wheel((e, cx) => {
        this.scroll = Math.max(0, Math.min(this.scroll - e.delta.y, this.maxScroll));
        while (this.at < rows.length - 1 && tops[this.at] < this.scroll) this.at++;
        while (this.at > 0 && tops[this.at] + ROW_H > this.scroll + LIST_H) this.at--;
        cx.notify();
      })
      .children(fixed ? items : [v_flex().children(items)]);
  }

  empty(t) {
    const kind = PREFIXES[this.text[0]];
    const q = this.text.slice(1).trim();
    const say =
      kind === "files" && this.files === null ? "Reading files…"
      : kind === "files" && this.problem ? this.problem
      : kind === "output" && this.outputReading ? "Reading what agents printed…"
      : kind === "prs" && !this.has.pr ? "Install Branch PR, with its helper, to search pull requests."
      : kind === "issues" && !this.has.issue ? "Install Branch Issue, with its helper, to search Linear issues."
      : (kind === "prs" || kind === "issues") && this[kind] === null ? (kind === "prs" ? "Searching GitHub…" : "Searching Linear…")
      : (kind === "prs" || kind === "issues") && this[kind]?.error ? this[kind].error
      : (kind === "prs" || kind === "issues") ? (q ? `No ${kind === "prs" ? "pull requests" : "issues"} match "${q}".` : `No open ${kind === "prs" ? "pull requests" : "issues"}.`)
      : kind === "output" && q.length < 2 ? "Type what an agent printed: an error, a file name, a question."
      : `Nothing matches "${this.text}".`;
    return div().px(16).py(14).text_size(13).text_color(t.dim).child(say);
  }

  move(rows, step) {
    let i = this.at;
    for (let n = 0; n < Math.abs(step); n++) {
      let j = i + Math.sign(step);
      while (rows[j]?.kind === "head") j += Math.sign(step);
      if (!rows[j]) break; // Stops at the ends: wrapping jumps out of sight.
      i = j;
    }
    this.at = i;
  }

  render() {
    const t = theme();
    const rows = this.compose ? [] : this.rows();
    // Opens on the tab you were in before, so Enter goes back; else where you are.
    if (this.at === null) {
      const back = rows.findIndex((r) => r.kind === "tab" && r.last);
      this.at = back >= 0 ? back : Math.max(0, rows.findIndex((r) => r.kind === "tab" && r.here), this.firstPick());
    }
    this.at = Math.min(this.at, Math.max(0, rows.length - 1));
    const chip = this.compose ? `Message to ${this.compose.name}:` : this.attach ? `Hand ${this.attach.rel} to` : null;
    const [left, right] = this.compose ? ["⌘↵ sends   ↵ new line", "Esc back"] : this.attach ? ["↵ picks the agent", "Esc back"] : this.hints(rows);
    return v_flex()
      .id("better-search")
      .track_focus(this.handle)
      .w_full()
      .min_h(0)
      .p(18)
      .gap(10)
      .bg(t.popover)
      .on_key_down((e, cx) => {
        const k = e.key;
        if (k === "escape") this.back(cx);
        else if (this.compose) return; // The textarea's own arrows and pages.
        else if (k === "down") this.move(rows, 1);
        else if (k === "up") this.move(rows, -1);
        else if (k === "pagedown") this.move(rows, SHOWN);
        else if (k === "pageup") this.move(rows, -SHOWN);
        else if (k === "tab" && drill(rows, this.at, this.text)) this.setText(drill(rows, this.at, this.text));
        else return;
        cx.stop_propagation();
        cx.notify();
      })
      .when(Boolean(this.compose), (el) => el.child(
        v_flex().gap(8).p(10).rounded(9).border_1().border_color(t.accent).bg(t.background)
          .child(h_flex().gap(10).items_center()
            .child(div().flex_1().truncate().text_size(12).text_color(t.accent).child(chip))
            .child(div().text_size(11).text_color(t.dim).child("Esc")))
          .child(Textarea.new(this.note).w_full().text_size(12.8).text_color(t.foreground))
          .when(Boolean(this.compose?.rel), (el) => el.child(h_flex().child(
            div().px(8).py(2).rounded(6).border_1().border_color(t.border).bg(t.raised).text_size(11.5).text_color(t.muted).truncate().child(`File: ${this.compose.rel}`),
          ))),
      ))
      .when(!this.compose, (el) => el.child(
        h_flex().h(36).flex_none().px(10).gap(10).items_center().rounded(9).border_1().border_color(t.accent).bg(t.background)
          .child(svg("mods/workspace-chrome/search.svg").size(15).text_color(t.dim))
          .when(Boolean(chip), (el) => el.child(div().flex_none().max_w(260).truncate().text_size(12).text_color(t.accent).child(chip)))
          .child(Input.new(this.input).flex_1().h_full().text_size(12.8).text_color(t.foreground))
          .child(div().text_size(11).text_color(t.dim).child("Esc")),
      ))
      .when(!this.compose && !this.attach, (el) => el.child(this.chips(t)))
      .when(Boolean(this.error), (el) => el.child(div().px(4).text_size(12).text_color(t.blocked).child(this.error)))
      .when(!this.compose, (el) => el.child(rows.length ? this.list(t, rows) : this.empty(t)))
      .child(h_flex().px(4).gap(16).text_size(11).text_color(t.dim)
        .child(div().flex_1().min_w(0).truncate().child(left))
        .child(div().flex_none().child(right)));
  }

  // One chip per prefix: the one typed is lit, and a click types it (or clears it).
  chips(t) {
    const on = this.text[0];
    return h_flex().flex_wrap().gap(6).children(CHIPS.map(([p, label]) =>
      // Drawn like Herdr's Settings sections: no frame, `raised` when chosen or pointed at.
      h_flex().id(`bs-chip-${label}`).gap(5).px(8).py(3).items_center().rounded(6).cursor_pointer()
        .bg(p === on ? t.raised : "#00000000")
        .hover((s) => s.bg(t.raised))
        .on_click((_e, cx) => {
          this.setText(p === on ? "" : p + this.text.slice(PREFIXES[on] ? 1 : 0));
          this.typed(cx);
          cx.notify();
        })
        .child(div().font_semibold().text_size(11.5).text_color(p === on ? t.accent : t.dim).child(p))
        .child(div().text_size(11.5).text_color(p === on ? t.foreground : t.muted).child(label)),
    ));
  }

  // The footer: what the selected row can do.
  hints(rows) {
    const r = rows[this.at];
    const does = !r || r.kind === "head" ? []
      : r.kind === "command" ? ["↵ run"]
      : r.kind === "file" ? ["↵ open", "⌘↵ hand to agent"]
      : r.kind === "pr" || r.kind === "issue" ? ["↵ open in its panel", "⌘↵ open link"]
      : r.agent ? ["↵ go", "⇧↵ peek", "⌘↵ message"]
      : ["↵ go"];
    if (drill(rows, this.at, this.text) && !PREFIXES[this.text[0]]) does.push("⇥ all");
    return [does.join("   "), "Esc close"];
  }
}
