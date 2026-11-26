import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Stand in for the desktop host. Record text passed to the real sidebar view.
const host = {
  herdr: "export const theme = () => ({}); export function setExec(fn) { exec = fn; } export let exec, shared, setShared, settings, appHome, readTextFile, watchFolder;",
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

test("linked and open issue rows each offer a separate checkout button", async () => {
  const { clicks, div } = await import("gpui-kit");
  const { renderGitHubPanel } = await import("../../herdr/estro/mods/branch-issue/github/panel.js");
  const issue = { number: 7, repository: "owner/app", title: "Fix menu", url: "https://github.com/owner/app/issues/7" };
  const data = { repository: "owner/app", linked: [issue], items: [issue] };
  const actions = [];
  renderGitHubPanel(div(), { key: "space", data }, [], {
    open: (item, repository, key) => actions.push([item, repository, key]),
  });
  const urls = [];
  const cx = { open_url: (url) => urls.push(url), stop_propagation() {} };
  for (const group of ["github-linked", "github-open"]) {
    const id = group + "-owner/app#7";
    clicks.get(id)(null, cx);
    clicks.get(id + "-worktree")(null, cx);
  }
  assert.deepEqual(urls, [issue.url, issue.url]);
  assert.deepEqual(actions, [[issue, "owner/app", "space"], [issue, "owner/app", "space"]]);
});
