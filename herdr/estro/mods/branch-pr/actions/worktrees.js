// Checkouts of a PR: those that exist, and making a new one as a new space.
import { InputState } from "gpui-base";
import { spaces, exec, home, appHome, readTextFile, run, knownAgents } from "herdr";
import { repositoryFromRemote } from "../github/model.js";

const DEFAULT_WORKTREE_ROOT = "~/.herdr/worktrees";
const WORKTREE_TIMEOUT_MS = 600_000;

// Match Herdr's worktree folder names, including names outside ASCII.
export function slug(text) {
  const normalized = text.normalize("NFC");
  const name = normalized
    .replace(/[^\p{L}\p{M}\p{N}._-]+/gu, "-")
    .replace(/^-+|-+$/g, "");
  if (name) return name;
  let hash = 2166136261;
  for (const char of normalized) hash = Math.imul(hash ^ char.codePointAt(0), 16777619);
  return `branch-${(hash >>> 0).toString(16).padStart(8, "0")}`;
}

async function resolveUserHome(machine) {
  if (!machine) return home();
  let result;
  try {
    result = await exec("sh", ["-c", 'printf %s "$HOME"'], { on: machine });
  } catch {}
  if (!result || result.code !== 0 || !result.stdout?.trim())
    result = await exec(
      "powershell.exe",
      ["-NoProfile", "-Command", "[Console]::Write($HOME)"],
      { on: machine },
    );
  if (result.code !== 0 || !result.stdout?.trim())
    throw new Error("Could not find the remote home folder.");
  return result.stdout.trim().replace(/\\/g, "/");
}

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
  worktreeKey() {
    return `${this.pr?.repository}#${this.pr?.number}`;
  },

  // Worktrees already checked out for this PR: those on its head branch, as when the
  // PR was opened from one, and branches bound through `branch.<name>.herdr-pr`.
  loadWorktrees(cx) {
    const { sp, pr } = this;
    if (!sp || !pr) return;
    const repo = pr.repository;
    const key = this.worktreeKey();
    cx.spawn(async (cx) => {
      const options = { cwd: sp.folder, on: sp.machine };
      const bound = await exec(
        "git",
        ["config", "--get-regexp", "^branch\\..*\\.herdr-pr$"],
        options,
      );
      const branches = new Set();
      for (const line of (bound.stdout ?? "").split("\n")) {
        const match = /^branch\.(.+)\.herdr-pr (.+)$/.exec(line.trim());
        if (match && match[2].toLowerCase() === key.toLowerCase()) branches.add(match[1]);
      }
      // shortcut: matches the head branch by name, so a fork's same-named branch counts too.
      branches.add(pr.headRefName);
      const list = [];
      const out = await exec("git", ["worktree", "list", "--porcelain"], options);
      for (const block of (out.stdout ?? "").split("\n\n")) {
        const path = /^worktree (.+)$/m.exec(block)?.[1];
        const branch = /^branch refs\/heads\/(.+)$/m.exec(block)?.[1];
        if (path && branch && branches.has(branch))
          list.push({ path, branch, name: path.split(/[\\/]/).pop() });
      }
      if (this.pr?.number === pr.number && this.pr?.repository === repo)
        this.worktrees = { key, list };
      cx.notify();
    });
  },

  currentWorktrees() {
    return this.worktrees?.key === this.worktreeKey() ? this.worktrees.list : [];
  },

  worktreeSpace(worktree) {
    const machine = this.sp?.machine ?? null;
    return spaces().find((s) => s.folder === worktree.path && (s.machine ?? null) === machine);
  },

  showWorktree(cx) {
    if (!this.pr || !this.sp) return;
    // The PR's own branch name and PR-<number>; a PR may already have
    // checkouts, so each default skips the ones in use. Case is ignored because
    // macOS folders treat pr-2 and PR-2 as the same name.
    const worktrees = this.currentWorktrees();
    const free = (base, taken) => {
      const used = new Set(taken.map((value) => value?.toLowerCase()));
      let value = base;
      for (let i = 2; used.has(value.toLowerCase()); i++) value = `${base}-${i}`;
      return value;
    };
    const branch = free(
      this.pr.headRefName,
      worktrees.map((w) => w.branch),
    );
    const name = free(
      `PR-${this.pr.number}`,
      worktrees.map((w) => w.name),
    );
    const form = {
      pr: this.pr,
      repo: this.pr.repository,
      sp: { ...this.sp },
      branch: InputState.new({ value: branch }),
      name: InputState.new({ value: name }),
      launch: this.settings.worktrees.open_with, // terminal or an installed agent's program key
      agents: [],
      root: this.settings.worktrees.root ?? DEFAULT_WORKTREE_ROOT,
    };
    this.worktreeForm = form;
    form.branch.on("change", (_e, cx) => cx.notify());
    form.name.on("change", (_e, cx) => cx.notify());
    form.branch.on("submit", (_e, cx) => this.createWorktree(cx));
    form.name.on("submit", (_e, cx) => this.createWorktree(cx));
    form.branch.focus();
    cx.spawn(async (cx) => {
      try {
        form.root = await worktreeRoot(
          await resolveUserHome(form.sp.machine),
          this.settings.worktrees.root,
        );
      } catch (error) {
        form.error = error.message;
      }
      try {
        const agents = await knownAgents({ on: form.sp.machine ?? null });
        if (this.worktreeForm === form) form.agents = agents.filter((a) => a.installed);
      } catch {}
      cx.notify();
    });
    cx.notify();
  },

  // Terminal plus each installed agent; the chosen one starts in the worktree's first tab.
  launchChoices(form) {
    return [{ key: "terminal", name: "Terminal" }, ...form.agents];
  },

  createWorktree(cx) {
    const form = this.worktreeForm;
    if (!form || form.busy || form.path) return;
    const branch = form.branch.value().trim();
    const name = form.name.value().trim();
    form.error = null;
    if (!name || !name.trim()) {
      form.error = "Enter a worktree name.";
      cx.notify();
      return;
    }
    const { sp, repo, pr } = form;
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
        const checked = await git(["check-ref-format", "--branch", branch]);
        if (checked !== branch) throw new Error("Enter a literal branch name.");
        const remotes = (await git(["remote"])).split("\n").filter(Boolean);
        let url;
        for (const remote of remotes) {
          const candidate = await git(["remote", "get-url", remote]);
          try {
            if (repositoryFromRemote(candidate).toLowerCase() === repo.toLowerCase()) {
              url = candidate;
              break;
            }
          } catch {}
        }
        if (!url)
          throw new Error(
            "This space has no remote for this PR’s repository. Open a space for that repository first.",
          );
        const existing = await exec(
          "git",
          ["show-ref", "--verify", "--quiet", `refs/heads/${branch}`],
          { cwd: sp.folder, on: sp.machine },
        );
        if (existing.code === 0)
          throw new Error("That branch already exists. Choose a new branch name.");
        if (existing.code !== 1)
          throw new Error(existing.stderr?.trim() || "Could not check existing branches.");
        const user = await resolveUserHome(sp.machine);
        const root = await worktreeRoot(user, this.settings.worktrees.root);
        form.root = root;
        const folder = slug(name);
        if (folder === "." || folder === "..") throw new Error("Choose a worktree name other than . or ..");
        const path = `${root.replace(/\/+$/, "")}/${repo.replace(/\//g, "-")}/${folder}`;
        // Pin the checkout to a verified commit, not a moving PR branch. If
        // GitHub and FETCH_HEAD disagree, stop rather than open the wrong code.
        const latest = await this.api({ action: "detail", repo, number: pr.number }, sp);
        if (!/^[0-9a-f]{40,64}$/i.test(latest.headRefOid ?? ""))
          throw new Error("The PR has no valid head commit.");
        await git(["fetch", "--no-tags", "--", url, `refs/pull/${pr.number}/head`]);
        if ((await git(["rev-parse", "FETCH_HEAD"])) !== latest.headRefOid)
          throw new Error("The PR changed while fetching. Try again.");
        const result = await exec(
          "git",
          ["worktree", "add", "-b", branch, "--", path, latest.headRefOid],
          { cwd: sp.folder, on: sp.machine, timeout: WORKTREE_TIMEOUT_MS },
        );
        if (result.code !== 0)
          throw new Error(result.stderr?.trim() || result.stdout?.trim() || "Git command failed.");
        // Retain the checkout if opening its terminal fails, so retry cannot create it twice.
        form.path = path;
        form.createdName = name;
        await git(["config", `branch.${branch}.herdr-pr`, `${repo}#${pr.number}`]);
        this.openWorktree(form, cx);
      } catch (error) {
        form.error = error.message;
      } finally {
        form.busy = false;
        cx.notify();
      }
    });
  },

  // A new space for the checkout: the spaces sidebar nests it under the repo at
  // once, and its first tab (a shell or the chosen agent) takes focus.
  openWorktree(form, cx) {
    const agent = form.agents.find((a) => a.key === form.launch);
    try {
      run("space.new", {
        folder: form.path,
        machine: form.sp.machine ?? "",
        tab: form.createdName,
        ...(agent ? { argv: agent.run } : {}),
      });
      form.opened = true;
      form.error = null;
      if (this.worktreeForm === form) this.worktreeForm = null;
      this.loadWorktrees(cx);
    } catch (error) {
      form.error = `Worktree created at ${form.path}. Could not open its space: ${error.message}`;
    }
    cx.notify();
  },
};
