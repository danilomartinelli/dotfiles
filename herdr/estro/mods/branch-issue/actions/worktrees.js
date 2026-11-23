// Starting work on an issue: its checkouts, and making a new one as a new space.
import { InputState } from "gpui-base";
import { spaces, exec, home, appHome, readTextFile, run, knownAgents } from "herdr";
import { folderName, identifiersIn, issuePrompt, slug } from "../linear/model.js";

const BRANCH_LIMIT = 100;
const DEFAULT_WORKTREE_ROOT = "~/.herdr/worktrees";
const WORKTREE_TIMEOUT_MS = 600_000;

async function worktreeRoot(user, fallback) {
  const raw = await readTextFile(`${appHome()}/settings.json`);
  const settings = raw === null ? {} : JSON.parse(raw);
  const directory = settings?.worktrees?.directory ?? fallback ?? DEFAULT_WORKTREE_ROOT;
  if (typeof directory !== "string" || !directory.trim())
    throw new Error("worktrees.directory must be a non-empty path.");
  let path = directory.replace(/\\/g, "/");
  if (path === "~" || path.startsWith("~/"))
    path = user.replace(/\\/g, "/").replace(/\/$/, "") + path.slice(1);
  if (!path.startsWith("/") && !/^[A-Za-z]:\//.test(path))
    throw new Error("worktrees.directory must be an absolute path or start with ~/.");
  path = path.replace(/\/+$/, "");
  return path || "/";
}

export const worktreeMethods = {
  // Worktrees already checked out for this issue: branches whose
  // `branch.<name>.herdr-issue` binding names it, joined to `git worktree list`.
  loadWorktrees(cx) {
    const { sp, issue } = this;
    if (!sp || !issue) return;
    const identifier = issue.identifier;
    cx.spawn(async (cx) => {
      const options = { cwd: sp.folder, on: sp.machine };
      const bound = await exec(
        "git",
        ["config", "--get-regexp", "^branch\\..*\\.herdr-issue$"],
        options,
      );
      const branches = new Set();
      for (const line of (bound.stdout ?? "").split("\n")) {
        const match = /^branch\.(.+)\.herdr-issue (.+)$/.exec(line.trim());
        if (match && identifiersIn(match[2]).includes(identifier)) branches.add(match[1]);
      }
      const list = [];
      if (branches.size) {
        const out = await exec("git", ["worktree", "list", "--porcelain"], options);
        for (const block of (out.stdout ?? "").split("\n\n")) {
          const path = /^worktree (.+)$/m.exec(block)?.[1];
          const branch = /^branch refs\/heads\/(.+)$/m.exec(block)?.[1];
          if (path && branch && branches.has(branch))
            list.push({ path, branch, name: folderName(path) });
        }
      }
      if (this.issue?.identifier === identifier) this.worktrees = { identifier, list };
      cx.notify();
    });
  },

  currentWorktrees() {
    return this.worktrees?.identifier === this.issue?.identifier ? this.worktrees.list : [];
  },

  worktreeSpace(worktree) {
    const machine = this.sp?.machine ?? null;
    return spaces().find((s) => s.folder === worktree.path && (s.machine ?? null) === machine);
  },

  // Open the form. Linear computes `branchName` with the team's convention; a
  // numeric suffix skips branches that already have a worktree here.
  showWorktree(cx) {
    if (!this.issue || !this.sp) return;
    const taken = new Set(this.currentWorktrees().map((w) => w.branch));
    const base =
      this.issue.branchName || slug(`${this.issue.identifier}-${this.issue.title}`).slice(0, 60);
    let branch = base;
    for (let i = 2; taken.has(branch); i++) branch = `${base}-${i}`;
    const form = {
      issue: this.issue,
      sp: { ...this.sp },
      branch: InputState.new({ value: branch }),
      name: InputState.new({ value: slug(branch) }),
      base: "main", // the remote's HEAD once it's known, unless one has been picked
      launch: this.settings.worktrees.open_with, // terminal or an installed agent's program key
      agents: [],
      start: this.settings.worktrees.move_to_started, // move the issue to started after creation
    };
    this.worktreeForm = form;
    // The worktree name follows the branch until the person edits it themselves.
    form.branch.on("change", (_e, cx) => {
      if (!form.nameEdited) form.name.set_value(slug(form.branch.value().trim()));
      cx.notify();
    });
    form.name.on("change", (_e, cx) => {
      form.nameEdited = form.name.value() !== slug(form.branch.value().trim());
      cx.notify();
    });
    for (const input of [form.branch, form.name])
      input.on("submit", (_e, cx) => this.createWorktree(cx));
    form.branch.focus();
    cx.spawn(async (cx) => {
      try {
        form.root = await worktreeRoot(
          await this.homeOf(form.sp),
          this.settings.worktrees.root,
        );
      } catch (error) {
        form.error = error.message;
      }
      cx.notify();
    });
    // The base defaults to the remote's HEAD; the launch choices to what is installed.
    cx.spawn(async (cx) => {
      try {
        const head = await exec(
          "git",
          ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
          { cwd: form.sp.folder, on: form.sp.machine },
        );
        const name = head.code === 0 ? head.stdout.trim().replace(/^origin\//, "") : "";
        if (name && this.worktreeForm === form && !form.basePicked) form.base = name;
        form.branches = await this.branchChoices(form.sp);
        cx.notify();
        // The list is what there is to pick from, so bring in branches pushed since.
        const fetched = await exec("git", ["fetch", "--no-tags", "origin"], {
          cwd: form.sp.folder,
          on: form.sp.machine,
        });
        if (fetched.code === 0) form.branches = await this.branchChoices(form.sp);
        const agents = await knownAgents({ on: form.sp.machine ?? null });
        if (this.worktreeForm === form) form.agents = agents.filter((a) => a.installed);
      } catch {}
      cx.notify();
    });
    cx.notify();
  },

  // Branches to start from, for stacking on another one: this checkout's first, then the
  // most recently changed, whether local or only on origin.
  async branchChoices(sp) {
    const options = { cwd: sp.folder, on: sp.machine };
    const current = await exec("git", ["branch", "--show-current"], options);
    const refs = await exec(
      "git",
      ["for-each-ref", "--sort=-committerdate", "--format=%(refname)", "refs/heads", "refs/remotes/origin"],
      options,
    );
    const names = (refs.stdout ?? "")
      .split("\n")
      .filter((ref) => ref && ref !== "refs/remotes/origin/HEAD")
      .map((ref) => ref.replace(/^refs\/(heads|remotes\/origin)\//, ""));
    const here = current.code === 0 ? current.stdout.trim() : "";
    return [...new Set([...(here ? [here] : []), ...names])].slice(0, BRANCH_LIMIT);
  },

  launchChoices(form) {
    return [{ key: "terminal", name: "Terminal" }, ...form.agents];
  },

  createWorktree(cx) {
    const form = this.worktreeForm;
    if (!form || form.busy || form.path) return;
    const branch = form.branch.value().trim();
    const name = form.name.value().trim();
    const base = form.base;
    form.error = null;
    if (!name) {
      form.error = "Enter a worktree name.";
      cx.notify();
      return;
    }
    const { sp, issue } = form;
    form.busy = true;
    cx.notify();
    cx.spawn(async (cx) => {
      const git = async (args) => {
        const result = await exec("git", args, { cwd: sp.folder, on: sp.machine });
        if (result.code !== 0)
          throw new Error(result.stderr?.trim() || result.stdout?.trim() || "Git command failed.");
        return result.stdout.trim();
      };
      try {
        if ((await git(["check-ref-format", "--branch", branch])) !== branch)
          throw new Error("Enter a literal branch name.");
        const existing = await exec(
          "git",
          ["show-ref", "--verify", "--quiet", `refs/heads/${branch}`],
          { cwd: sp.folder, on: sp.machine },
        );
        if (existing.code === 0)
          throw new Error("That branch already exists. Choose a new branch name.");
        if (existing.code !== 1)
          throw new Error(existing.stderr?.trim() || "Could not check existing branches.");
        const user = await this.homeOf(sp);
        const root = await worktreeRoot(user, this.settings.worktrees.root);
        form.root = root;
        const folder = slug(name);
        if (folder === "." || folder === "..")
          throw new Error("Choose a worktree name other than . or ..");
        const path = `${root.replace(/\/+$/, "")}/${folderName(sp.folder)}/${folder}`;
        const start = await this.worktreeStart(base, sp);
        const added = await exec(
          "git",
          ["worktree", "add", "-b", branch, "--", path, start],
          { cwd: sp.folder, on: sp.machine, timeout: WORKTREE_TIMEOUT_MS },
        );
        if (added.code !== 0)
          throw new Error(added.stderr?.trim() || added.stdout?.trim() || "Git command failed.");
        // Retain the checkout if opening its space fails, so retry cannot create it twice.
        form.path = path;
        form.createdName = name;
        await git(["config", `branch.${branch}.herdr-issue`, issue.identifier]);
        if (form.start) {
          const started = (issue.team?.states ?? []).find((s) => s.type === "started");
          if (started && issue.state?.id !== started.id)
            await this.api({ action: "update", issue: issue.id, stateId: started.id }, sp);
        }
        this.openWorktree(form, cx);
      } catch (error) {
        form.error = error.message;
      } finally {
        form.busy = false;
        cx.notify();
      }
    });
  },

  // Where a new branch starts: the remote's base, so it isn't behind, unless the local
  // branch has everything the remote does. Stacking needs that: a parent branch may have
  // commits not pushed yet, or not be on the remote at all.
  async worktreeStart(base, sp) {
    const options = { cwd: sp.folder, on: sp.machine };
    const local = `refs/heads/${base}`;
    const fetched = await exec("git", ["fetch", "--no-tags", "origin", base], options);
    const hasLocal =
      (await exec("git", ["show-ref", "--verify", "--quiet", local], options)).code === 0;
    if (fetched.code !== 0) {
      if (hasLocal) return local;
      throw new Error(fetched.stderr?.trim() || `No branch ${base} here or on origin.`);
    }
    if (!hasLocal) return "FETCH_HEAD";
    const ahead = await exec("git", ["merge-base", "--is-ancestor", "FETCH_HEAD", local], options);
    return ahead.code === 0 ? local : "FETCH_HEAD";
  },

  // The home folder on the space's machine, where ~/.herdr/worktrees lives.
  async homeOf(sp) {
    if (!sp.machine) return home();
    let result = await exec("sh", ["-c", 'printf %s "$HOME"'], { on: sp.machine });
    if (result.code !== 0 || !result.stdout.trim())
      result = await exec("powershell.exe", ["-NoProfile", "-Command", "[Console]::Write($HOME)"], {
        on: sp.machine,
      });
    if (result.code !== 0 || !result.stdout.trim())
      throw new Error("Could not find the remote home folder.");
    return result.stdout.trim().replace(/\\/g, "/");
  },

  // A new space for the checkout: nested under the repo at once, with a shell
  // or the chosen agent in its first tab. An agent gets the issue as its prompt.
  openWorktree(form, cx) {
    const agent = form.agents.find((a) => a.key === form.launch);
    try {
      run("space.new", {
        folder: form.path,
        machine: form.sp.machine ?? "",
        tab: form.createdName,
        ...(agent ? { argv: [...agent.run, issuePrompt(form.issue)] } : {}),
      });
      form.opened = true;
      form.error = null;
      if (this.worktreeForm === form) this.worktreeForm = null;
      // Reload the detail when the state moved, else only the worktree list.
      if (form.start) this.openIssue(form.issue.identifier, cx);
      else this.loadWorktrees(cx);
    } catch (error) {
      form.error = `Worktree created at ${form.path}. Could not open its space: ${error.message}`;
    }
    cx.notify();
  },
};
