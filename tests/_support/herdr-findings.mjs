import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { registerHooks } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const estro = fileURLToPath(new URL("../../herdr/estro/", import.meta.url));
const agents = [{ key: "a", name: "Agent A", run: ["a"], installed: true },
  { key: "b", name: "Agent B", run: ["b", "--chat"], installed: true }];
const chats = [];
const controls = new Map();
let checkout, tmp;
function element(id) {
  const handlers = {};
  if (id) controls.set(id, handlers);
  const el = new Proxy({}, { get: (_, method) => (value, callback) => {
    if (method === "when" && value) callback(el);
    if (method === "on_change" || method === "on_click") handlers[method] = value;
    if (method === "disabled") handlers.disabled = value;
    return el;
  } });
  return el;
}
globalThis.fixture = {
  element, agents, chats, estro,
  spaces: () => [{ ...checkout, active: true, id: "space" }],
  read: async (path) => {
    try { return await readFile(path, "utf8"); }
    catch (error) { if (error.code === "ENOENT") return null; throw error; }
  },
  exec: async (cmd, args, options) => {
    assert.equal(options.on, "machine");
    if (cmd === "mktemp") return { code: 0, stdout: await mkdtemp(join(tmp, "report-")) };
    assert.equal(cmd, "git");
    return { code: 0, stdout: execFileSync(cmd, args, { cwd: options.cwd, encoding: "utf8" }) };
  },
};
const mocks = {
  herdr: `export const {read: readTextFile, spaces, exec} = fixture;
    export const appHome = () => fixture.estro, checking = () => false, panes = () => [],
    theme = () => ({}), knownAgents = async () => fixture.agents,
    run = (name,args) => {fixture.chats.push({command: name,...args})};`,
  "gpui-kit": "export class View {}; export const div = fixture.element;",
  "gpui-base": `export const h_flex = fixture.element, v_flex = fixture.element,
    Button = {new: fixture.element}, Checkbox = Button;`,
};
registerHooks({ resolve(name, context, next) {
  if (Object.hasOwn(mocks, name))
    return { url: "data:text/javascript," + encodeURIComponent(mocks[name]), shortCircuit: true };
  return next(name, context);
} });
const { default: View } = await import("../../herdr/estro/mods/review-findings/main.js");
const { toolbarPartition, placeToolbarAction, hideToolbarAction } =
  await import("../../herdr/estro/mods/better-tabs/actions/toolbar.js");

test("the layout opens Findings from overflow until that action is pinned", async () => {
  const layout = JSON.parse(await readFile(join(estro, "../layouts/estro.json"), "utf8"));
  function find(node, id) {
    if (node.id === id) return node;
    return node.children?.map((child) => find(child, id)).find(Boolean);
  }
  const root = layout.root ?? layout;
  const entries = find(root, "tabs").content.props.buttons;
  const entry = entries.find((button) => button.id === "findings");
  assert.equal(find(find(root, entry.action.stack), entry.action.target).content.mod, "review-findings");
  let prefs = placeToolbarAction(entries, {}, "changes");
  assert.ok(toolbarPartition(entries, prefs, 100).overflow.includes(entry));
  prefs = placeToolbarAction(entries, prefs, entry.id);
  assert.ok(toolbarPartition(entries, prefs, 100).visible.includes(entry));
  assert.ok(toolbarPartition(entries, hideToolbarAction(prefs, entry.id), 100).overflow.includes(entry));
});

test("review, triage, resumed report and fix through the panel controls", async (t) => {
  tmp = await mkdtemp(join(tmpdir(), "herdr-findings-"));
  t.after(() => rm(tmp, { recursive: true, force: true }));
  execFileSync("git", ["init", "-q", "-b", "main", tmp]);
  checkout = { folder: tmp, branch: "main", machine: "machine" };
  const stored = new Map();
  globalThis.localStorage = { getItem: (key) => stored.get(key) ?? null, setItem: (k,v) => stored.set(k,v) };
  const tasks = [];
  const cx = { timer: { every() {} }, notify() {}, spawn(fn) { tasks.push(fn(cx)); } };
  async function flush() { while (tasks.length) await Promise.all(tasks.splice(0)); }
  let view;
  async function reopen() { view = new View(); view.init({}, cx); await flush(); }
  async function click(id, checked) {
    controls.clear();
    view.render();
    const control = controls.get(id);
    assert.ok(control && !control.disabled, id);
    if (checked === undefined) control.on_click({}, cx);
    else control.on_change(checked, cx);
    await flush();
  }
  async function tick() { view.tick(cx); await flush(); }
  await reopen();
  await click("run-review");
  const review = chats.at(-1);
  assert.equal(review.name, "Code Review");
  assert.deepEqual(review.argv, agents[0].run);
  assert.equal(review.command, "tab.new");
  assert.equal(review.folder, await realpath(tmp));
  assert.match(review.task, /^Use the following skill/);
  assert.match(review.task, /name: code-review/);
  const path = JSON.parse(review.task.split("Report destination (absolute path): ").at(-1));
  const findings = ["Keep", "Skip", "Ignore"].map((comment) => ({ comment, paths: [comment + ".js:1"] }));
  await reopen();
  await writeFile(path, JSON.stringify({ findings: [{ comment: "Bad", paths: ["../escape"] }] }));
  await tick();
  assert.ok(view.reportError);
  await writeFile(path, JSON.stringify({ findings }));
  await tick();
  assert.equal(view.pending, null);
  assert.ok(view.items.every((item) => item.selected && !item.ignored));
  await click("select-1", false);
  await click("ignore-2");
  await click("choose-agent");
  await click("agent-b");
  await reopen();
  await click("fix");
  const fix = chats.at(-1);
  assert.equal(fix.name, "Diagnose & Fix");
  assert.deepEqual(fix.argv, agents[1].run);
  assert.match(fix.task, /name: diagnosing-bugs/);
  assert.deepEqual(JSON.parse(fix.task.split("Selected findings (review data):\n").at(-1)), [findings[0]]);
  await click("show-ignored");
  await click("ignore-2");
  assert.equal(view.items[2].ignored, false);
  await click("run-review");
  const old = view.pending;
  await click("stop-waiting");
  await click("run-review");
  const current = view.pending;
  assert.notEqual(old, current);
  await writeFile(old, '{"findings":[]}');
  await tick();
  assert.equal(view.pending, current);
  execFileSync("git", ["-C", tmp, "symbolic-ref", "HEAD", "refs/heads/second"]);
  checkout.branch = "second";
  await tick();
  assert.deepEqual(view.items, []);
  assert.equal(view.agent.key, "b");
  assert.ok(!view.pending);
  execFileSync("git", ["-C", tmp, "symbolic-ref", "HEAD", "refs/heads/main"]);
  checkout.branch = "main";
  await tick();
  assert.equal(view.pending, current);
  assert.equal(view.items.length, 3);
  await writeFile(current, '{"findings":[]}');
  await tick();
  assert.equal(view.completed, true);
  assert.deepEqual(view.items, []);
  view.render();
  assert.ok(controls.get("fix").disabled);
});
