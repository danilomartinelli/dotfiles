import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Stand in for the desktop host. Record text passed to the real sidebar view.
const host = {
  herdr: `
    import { writeFile } from "node:fs/promises";
    export const writeTextFile = (path, value) => writeFile(path, value, { flag: "wx" });
    export const theme = () => ({});
    export function setExec(fn) { exec = fn; }
    export const checking = () => false;
    export function setWatch(fn) { watchFolder = fn; }
    const values = new Map();
    export function setShared(key, value) { values.set(key, value); }
    export function shared(key) { return values.get(key); }
    export let exec, settings, appHome, readTextFile, watchFolder, spaces, panes, focused, knownAgents, run;`,
  "gpui-kit": `
    export const text = [];
    export const clicks = new Map();
    export function div() {
      let id;
      const element = new Proxy({}, {
        get: (_, method) => (value, apply) => {
          if (method === "id") id = value;
          if (method === "when" && value) apply(element);
          if (method === "on_click") clicks.set(id, value);
          if (method === "child" && typeof value === "string") text.push(value);
          return element;
        },
      });
      return element;
    }
    export { div as svg }; export let image;`,
  "gpui-base": 'export { div as v_flex, div as h_flex } from "gpui-kit"; export let Popover, Input, Textarea, TextView;',
};
registerHooks({
  resolve(name, context, next) {
    if (Object.hasOwn(host, name))
      return { url: "data:text/javascript," + encodeURIComponent(host[name]), shortCircuit: true };
    return next(name, context);
  },
});

const { discoveryMethods } = await import("../../herdr/estro/mods/branch-pr/github/discovery.js");
const { sidebarMethods } = await import("../../herdr/estro/mods/better-changes/views/sidebar.js");
const { text } = await import("gpui-kit");

async function prSidebar(t) {
  const { PRStatusObserver, prAppearance, prPlaceKey } = await import("../../herdr/estro/mods/better-sidebar/git/pr-status.js");
  const { setExec } = await import("herdr");
  const observer = new PRStatusObserver();
  const place = { folder: "/tree", branch: "topic" };
  const repo = "owner/project";
  const pr = { number: 7, state: "OPEN", headRefName: place.branch,
    headRepository: { nameWithOwner: repo }, mergeStateStatus: "CLEAN" };
  let now = 10000;
  let hold;
  t.mock.method(Date, "now", () => now);
  setExec(async (cmd, args) => {
    if (cmd === "gh") {
      assert.deepEqual(args.slice(0, 4), ["pr", "list", "--repo", repo]);
      const response = { code: 0, stdout: JSON.stringify([pr]) };
      if (hold) await hold;
      return response;
    }
    assert.equal(cmd, "git");
    if (args.includes("symbolic-ref")) return { code: 0, stdout: place.branch };
    if (args.includes("config")) return { code: 1, stdout: "" };
    if (args.includes("get-url")) return { code: 0, stdout: "https://github.com/" + repo };
    return { code: 0, stdout: "origin" };
  });
  const tasks = [];
  const cx = { notify() {}, spawn(fn) { tasks.push(fn(cx)); } };
  function refresh(ms) {
    now += ms;
    observer.refresh([place], cx);
  }
  async function tick(ms) {
    refresh(ms);
    await Promise.all(tasks.splice(0));
    const entry = observer.entries.get(prPlaceKey(null, place.folder));
    return prAppearance(entry.prs[0], {}).label;
  }
  assert.equal(await tick(0), "Ready to merge");
  return { pr, repo, cx, tick, tasks, refresh, holdResponse(promise) { hold = promise; } };
}

test("external check failures and closure reach the sidebar on an idle checkout", async (t) => {
  const { pr, tick } = await prSidebar(t);
  pr.statusCheckRollup = [{ status: "IN_PROGRESS", conclusion: "" }, { conclusion: "SKIPPED" }];
  assert.equal(await tick(15000), "Checks pending");
  pr.statusCheckRollup = [{ status: "COMPLETED", conclusion: "FAILURE" }];
  assert.equal(await tick(15000), "Checks failed");
  pr.state = "CLOSED";
  assert.equal(await tick(15000), "Closed");
});

test("merging from Branch PR refreshes the sidebar on the next tick", async (t) => {
  const { changeMethods } = await import("../../herdr/estro/mods/branch-pr/actions/changes.js");
  const { pr, repo, cx, tick, tasks } = await prSidebar(t);
  const panel = { spaceKey: "tree", stateChange: { repo, number: pr.number, event: "merge" },
    api: async () => { pr.state = "MERGED"; }, openPR() {} };
  changeMethods.changeState.call(panel, cx);
  await Promise.all(tasks.splice(0));
  assert.equal(await tick(250), "Merged");
});

test("an in-flight lookup cannot mask a close after navigating away from Branch PR", async (t) => {
  const { changeMethods } = await import("../../herdr/estro/mods/branch-pr/actions/changes.js");
  const { pr, repo, cx, tick, tasks, refresh, holdResponse } = await prSidebar(t);
  const slow = Promise.withResolvers();
  holdResponse(slow.promise);
  refresh(15000);
  const [oldRead] = tasks.splice(0);
  await new Promise((done) => setImmediate(done));
  const panel = { spaceKey: "tree", stateChange: { repo, number: pr.number, event: "close" },
    api: async () => { pr.state = "CLOSED"; panel.spaceKey = "other"; }, openPR() {} };
  changeMethods.changeState.call(panel, cx);
  await Promise.all(tasks.splice(0));
  slow.resolve();
  await oldRead;
  assert.equal(await tick(250), "Closed");
});

test("switching spaces while a PR opens allows the new branch PR to open", () => {
  const opened = [];
  const panel = {
    ...discoveryMethods,
    view: "branch",
    opening: { number: 1 },
    detailLoading: true,
    detailToken: 1,
    leavePR() {},
    rememberView() {},
    loadNewAgents() {},
    refresh() {},
    search: { value: () => "" },
    openPR(number) { opened.push(number); },
  };
  panel.changeSpace({ folder: "/second" }, "second", {});
  panel.branchPRs = [{ number: 2 }];
  panel.openSoleBranchPR({});
  assert.equal(panel.detailToken, 2);
  assert.deepEqual(opened, [2]);
});

test("a clean checkout stays visible while its status refreshes", () => {
  const panel = {
    files: [],
    settings: { limits: { files: 10 } },
    loading: true,
    addGroup() {},
    renderCommitBox() {},
  };
  function renderText() {
    text.length = 0;
    sidebarMethods.renderChanges.call(panel);
    return text;
  }
  assert.deepEqual(renderText(), ["Loading changes…"]);
  panel.root = "/checkout";
  assert.deepEqual(renderText(), ["No changes"]);
});

test("a burst of filesystem events triggers one Changes refresh after it settles", async () => {
  const { gitMethods } = await import("../../herdr/estro/mods/better-changes/git/repository.js");
  const { setWatch } = await import("herdr");
  let emit, job, refreshes = 0;
  setWatch(() => {
    const pending = new Promise((resolve) => { emit = resolve; });
    pending.cancel = () => emit([]);
    return pending;
  });
  const timers = new Set();
  const cx = {
    spawn(fn) { job = fn(cx); },
    timer: { after(_ms, fn) {
      timers.add(fn);
      return { cancel: () => timers.delete(fn) };
    } },
  };
  const panel = { ...gitMethods, refresh() { refreshes++; } };
  panel.watch("/checkout", cx);
  for (let i = 0; i < 8; i++) {
    emit(["/checkout/output"]);
    await Promise.resolve();
  }
  assert.equal(refreshes, 0);
  assert.equal(timers.size, 1);
  for (const timer of timers) { timers.delete(timer); timer(cx); }
  assert.equal(refreshes, 1);
  emit(["/checkout/file"]);
  await Promise.resolve();
  panel.stopWatching();
  await job;
  assert.equal(timers.size, 0);
});

test("GitHub issue shortcut creates a tracking worktree and reopens it after a title edit", async (t) => {
  const { setExec } = await import("herdr");
  const { issueWorktree } = await import("../../herdr/estro/mods/branch-issue/github/worktree.js");
  const dir = mkdtempSync(join(tmpdir(), "issue worktree "));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
  const git = (args, cwd = dir) => {
    const r = spawnSync("git", args, { cwd, env, encoding: "utf8" });
    return { code: r.status, stdout: r.stdout, stderr: r.stderr };
  };
  const setup = (args) => assert.equal(git(args).code, 0);
  setup(["init", "--bare", "-b", "main", "upstream"]);
  setup(["clone", "upstream", "checkout"]);
  setup(["-C", "checkout", "-c", "user.name=Test", "-c", "user.email=test@example.org",
    "commit", "--allow-empty", "-m", "Initial"]);
  setup(["-C", "checkout", "push", "origin", "main"]);

  const sp = { folder: join(dir, "checkout"), machine: "builder" };
  const root = join(dir, "worktrees");
  const issue = { number: 7, title: "Fix café / menu!", repository: "owner/app",
    url: "https://github.com/owner/app/issues/7" };
  let developments = 0;
  let interruptFetch = true;
  setExec((command, args, options) => {
    if (command === "gh") {
      assert.equal(options?.on, undefined);
      assert.deepEqual(args, ["issue", "develop", issue.url, "--branch-repo", "owner/app", "--name", "7-fix-cafe-menu"]);
      if (!developments++) setup(["-C", "upstream", "branch", "7-fix-cafe-menu", "main"]);
      return { code: 0, stdout: "" };
    }
    assert.equal(command, "git");
    assert.equal(options.on, sp.machine);
    if (args[0] === "remote" && args[1] === "get-url")
      return { code: 0, stdout: "https://github.com/owner/app.git\n" };
    if (args[0] === "fetch" && interruptFetch) {
      interruptFetch = false;
      return { code: 1, stderr: "fetch interrupted" };
    }
    return git(args, options.cwd);
  });
  await assert.rejects(issueWorktree(sp, "other/app", issue, root), /repository changed/);
  await assert.rejects(issueWorktree(sp, "owner/app", issue, root), /fetch interrupted/);
  const path = await issueWorktree(sp, "owner/app", issue, root);
  assert.equal(git(["branch", "--show-current"], path).stdout.trim(), "7-fix-cafe-menu");
  assert.equal(git(["rev-parse", "--abbrev-ref", "@{upstream}"], path).stdout.trim(), "origin/7-fix-cafe-menu");
  assert.equal(git(["branch", "--show-current"], sp.folder).stdout.trim(), "main");
  issue.title = "Renamed issue";
  assert.equal(await issueWorktree(sp, "owner/app", issue, root), path);
  assert.equal(developments, 2);
});

test("linked and open issue rows distinguish the issue link, checkout and implementation chat", async () => {
  const { clicks, div } = await import("gpui-kit");
  const { renderGitHubPanel } = await import("../../herdr/estro/mods/branch-issue/github/panel.js");
  const issue = { number: 7, repository: "owner/app", title: "Fix menu", url: "https://github.com/owner/app/issues/7" };
  const data = { repository: "owner/app", linked: [issue], items: [issue] };
  const actions = [];
  renderGitHubPanel(div(), { key: "space", data }, [], {
    open: (item, repository, key, _cx, implement) => actions.push([item, repository, key, implement]),
  });
  const urls = [];
  const cx = { open_url: (url) => urls.push(url), stop_propagation() {} };
  for (const group of ["github-linked", "github-open"]) {
    const id = group + "-owner/app#7";
    clicks.get(id)(null, cx);
    clicks.get(id + "-worktree")(null, cx);
    clicks.get(id + "-implement")(null, cx);
  }
  assert.deepEqual(urls, [issue.url, issue.url]);
  assert.deepEqual(actions, [false, true, false, true].map((mode) => [issue, "owner/app", "space", mode]));
});

test("commit preference, rejected push and push-only retry use the same local commit", async (t) => {
  const { gitMethods } = await import("../../herdr/estro/mods/better-changes/git/repository.js");
  const { readPushTarget } = await import("../../herdr/estro/mods/better-changes/git/push.js");
  const dir = mkdtempSync(join(tmpdir(), "herdr push "));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const repo = join(dir, "checkout");
  const remote = join(dir, "remote");
  const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
  function git(args, cwd = repo) {
    const r = spawnSync("git", args, { cwd, env, encoding: "utf8" });
    return { code: r.status, stdout: r.stdout, stderr: r.stderr };
  }
  function ok(args, cwd) {
    const r = git(args, cwd);
    assert.equal(r.code, 0, r.stderr);
    return r.stdout.trim();
  }
  ok(["init", "-q", "-b", "main", repo], dir);
  ok(["init", "-q", "--bare", "-b", "main", remote], dir);
  ok(["config", "user.name", "Test"]);
  ok(["config", "user.email", "test@example.org"]);
  ok(["remote", "add", "origin", remote]);
  const saved = new Map();
  const storage = Object.getOwnPropertyDescriptor(globalThis, "localStorage");
  Object.defineProperty(globalThis, "localStorage", { configurable: true, value: {
    setItem: (key, value) => saved.set(key, value),
  } });
  t.after(() => {
    if (storage) Object.defineProperty(globalThis, "localStorage", storage);
    else delete globalThis.localStorage;
  });
  let operation;
  const cx = { notify() {}, spawn(fn) { operation = fn(cx); } };
  const panel = {
    ...gitMethods, root: repo, context: "repo", contextKey: () => "repo", git,
    input: { set_value() {} }, refresh() {}, commitMode: "commit", message: "Add file",
    stagedCount: 1, total: 1, amendToken: 0, pushTarget: await readPushTarget(git),
  };
  writeFileSync(join(repo, "file"), "first\n");
  ok(["add", "file"]);
  panel.setCommitMode("commit-push", cx);
  assert.equal(saved.get("commit-mode"), "commit-push");
  panel.commit(cx);
  await operation;
  assert.equal(panel.note, null);
  assert.equal(ok(["rev-parse", "main"], remote), ok(["rev-parse", "HEAD"]));
  assert.equal(ok(["rev-parse", "--abbrev-ref", "@{u}"]), "origin/main");
  assert.equal(panel.commitMode, "commit-push");

  ok(["switch", "-c", "topic", "--track", "origin/main"]);
  const mainHead = ok(["rev-parse", "main"], remote);
  const hook = join(remote, "hooks", "pre-receive");
  writeFileSync(hook, "#!/bin/sh\nexit 1\n", { mode: 0o755 });
  writeFileSync(join(repo, "file"), "second\n");
  ok(["add", "file"]);
  panel.message = "Edit file";
  panel.pushTarget = await readPushTarget(git);
  panel.commit(cx);
  await operation;
  assert.match(panel.note, /Committed locally\. Push failed/);
  assert.equal(panel.message, "");
  const committed = ok(["rev-parse", "HEAD"]);
  panel.total = panel.stagedCount = 0;
  panel.pushTarget = await readPushTarget(git);
  assert.equal(sidebarMethods.commitButtonLabel.call(panel), "Push");
  rmSync(hook);
  // Click Push during a poll. It must stay available, wait for that read,
  // then refresh the checkout again after the push finishes.
  const resumeRead = Promise.withResolvers();
  panel.location = () => ({ cwd: repo });
  panel.readRepository = () => resumeRead.promise;
  let refreshesAfterPush = 0;
  panel.refresh = () => { refreshesAfterPush++; };
  gitMethods.refresh.call(panel, cx);
  const read = operation;
  assert.equal(panel.canCommit(), true);
  panel.commit(cx);
  assert.equal(panel.busy, true);
  assert.equal(panel.canCommit(), false);
  await new Promise((done) => setImmediate(done));
  assert.equal(git(["show-ref", "--verify", "--quiet", "refs/heads/topic"], remote).code, 1);
  resumeRead.resolve();
  await read;
  await operation;
  assert.equal(panel.note, null);
  assert.equal(refreshesAfterPush, 1);
  assert.equal(ok(["rev-parse", "topic"], remote), committed);
  assert.equal(ok(["rev-parse", "main"], remote), mainHead);
  panel.pushTarget = await readPushTarget(git);
  assert.equal(panel.pushOnly(), false);
  panel.setCommitMode("commit", cx);
  assert.equal(saved.get("commit-mode"), "commit");
});

test("generate drafts from staged changes and preserve edits made while the provider runs", async (t) => {
  const { gitMethods } = await import("../../herdr/estro/mods/better-changes/git/repository.js");
  const { setExec } = await import("herdr");
  const tmp = mkdtempSync(join(tmpdir(), "herdr draft "));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  let operation, changeDuringGeneration;
  const cx = { notify() {}, spawn(fn) { operation = fn(cx); } };
  let snapshot = "index";
  const panel = {
    ...gitMethods, root: "/checkout", context: "remote", contextKey: () => "remote", stagedCount: 1,
    message: "", messageRevision: 0, messageProvider: "codex", input: { set_value() {} },
    git(args) {
      assert.ok(args.includes("--cached"));
      return { code: 0, stdout: args.includes("--raw") ? snapshot : "+staged code" };
    },
  };
  setExec((cmd, args, options) => {
    if (cmd === "mktemp") return { code: 0, stdout: mkdtempSync(join(tmp, "request ")) };
    if (cmd === "rm" || cmd === "rmdir") {
      rmSync(args.at(-1), { recursive: cmd === "rmdir" });
      return { code: 0 };
    }
    assert.equal(cmd, "sh");
    assert.ok(args.includes(panel.messageProvider));
    assert.ok(!args.join(" ").includes("staged code"));
    assert.match(readFileSync(join(options.cwd, "prompt"), "utf8"), /\+staged code/);
    changeDuringGeneration?.();
    return { code: 0, stdout: "Describe the change\n" };
  });
  panel.generateDraft(cx);
  await operation;
  assert.equal(panel.message, "Describe the change");
  panel.messageProvider = "claude";
  changeDuringGeneration = () => { panel.messageRevision++; panel.message = "My draft"; };
  panel.generateDraft(cx);
  await operation;
  assert.equal(panel.message, "My draft");
  changeDuringGeneration = () => { snapshot = "restaged"; };
  panel.generateDraft(cx);
  await operation;
  assert.match(panel.note, /Staged changes changed/);
  assert.equal(panel.message, "My draft");
});

test("discard confirms one unstaged path, preserves the index, and trashes only untracked files", async (t) => {
  const { discardMethods } = await import("../../herdr/estro/mods/better-changes/git/discard.js");
  const { readStatus } = await import("../../herdr/estro/mods/better-changes/git/reads.js");
  const { clicks } = await import("gpui-kit");
  const { setExec } = await import("herdr");
  const tmp = mkdtempSync(join(tmpdir(), "herdr discard "));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const repo = join(tmp, "repo");
  const trash = join(tmp, "recovered-files");
  mkdirSync(repo);
  mkdirSync(trash);
  writeFileSync(join(tmp, "trash"), '#!/bin/sh\nexec mv "$1" "$TEST_TRASH/"\n', { mode: 0o755 });
  const env = { ...process.env, PATH: tmp + ":" + process.env.PATH, TEST_TRASH: trash,
    GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
  function run(cmd, args) {
    const r = spawnSync(cmd, args, { cwd: repo, env, encoding: "utf8" });
    return { code: r.status, stdout: r.stdout, stderr: r.stderr };
  }
  const git = (args) => run("git", args);
  const ok = (args) => {
    const r = git(args);
    assert.equal(r.code, 0, r.stderr);
    return r.stdout;
  };
  ok(["init", "-q"]);
  const path = "-[ab].txt";
  const sibling = "-a.txt";
  const file = join(repo, path);
  writeFileSync(file, "original");
  writeFileSync(join(repo, sibling), "sibling");
  ok(["add", "."]);
  ok(["-c", "user.name=Test", "-c", "user.email=test@example.org", "commit", "-qm", "Initial"]);
  writeFileSync(file, "staged");
  ok(["--literal-pathspecs", "add", "--", path]);
  writeFileSync(file, "unstaged");
  writeFileSync(join(repo, sibling), "keep me");

  let job;
  const cx = { notify() {}, stop_propagation() {}, spawn(fn) { job = fn(cx); } };
  const panel = { ...sidebarMethods, ...discardMethods, git, context: "repo", root: repo,
    isCurrent(key) { return key === this.context; }, on: "machine", refresh() {}, view: "flat" };
  setExec((cmd, args, opts) => {
    assert.equal(opts.cwd, repo);
    assert.equal(opts.on, "machine");
    return run(cmd, args);
  });
  const click = (id) => clicks.get(id)(null, cx);
  async function ask(name) {
    const { files } = await readStatus(git);
    const entry = files.find((f) => f.path === name && f.unstaged);
    panel.fileRow(entry, "unstaged", 0);
    click("discard-" + name);
    panel.fileRow(entry, "unstaged", 0);
  }
  async function confirm() {
    job = undefined;
    click("confirm-discard");
    await job;
  }
  await ask(path);
  assert.equal(readFileSync(file, "utf8"), "unstaged");
  click("cancel-discard");
  await confirm(); // Even a queued click on the old confirmation has no effect.
  assert.equal(readFileSync(file, "utf8"), "unstaged");
  await ask(path);
  await confirm();
  assert.equal(panel.note, null);
  assert.equal(readFileSync(file, "utf8"), "staged");
  assert.equal(ok(["show", ":" + path]), "staged");
  assert.equal(readFileSync(join(repo, sibling), "utf8"), "keep me");
  rmSync(file);
  await ask(path);
  await confirm();
  assert.equal(readFileSync(file, "utf8"), "staged");

  const fresh = "-new [ab].txt";
  writeFileSync(join(repo, fresh), "new");
  await ask(fresh);
  ok(["--literal-pathspecs", "add", "--", fresh]);
  await confirm();
  assert.match(panel.note, /status changed/);
  assert.equal(readFileSync(join(repo, fresh), "utf8"), "new");
  ok(["--literal-pathspecs", "restore", "--staged", "--", fresh]);
  await ask(fresh);
  await confirm();
  assert.equal(panel.note, null);
  assert.equal(existsSync(join(repo, fresh)), false);
  assert.equal(readFileSync(join(trash, fresh), "utf8"), "new");
});
