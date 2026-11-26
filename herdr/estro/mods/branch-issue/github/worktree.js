// gh uses this computer's GitHub login. Git operates on the checkout's machine.
import { exec, knownAgents, run, shared, spaces } from "herdr";
import { checkout } from "./reads.js";

async function output(command) {
  const result = await command;
  if (result.code !== 0) throw new Error(result.stderr?.trim() || "The worktree command failed.");
  return result.stdout.trimEnd();
}

export async function implementationChat(issue, machine) {
  const installed = (await knownAgents({ on: machine })).filter((agent) => agent.installed && agent.run?.length);
  const preferred = shared("estro.chat-agent:" + JSON.stringify(machine ?? null));
  const agent = installed.find((entry) => entry.key === preferred) ?? installed[0];
  if (!agent) throw new Error("No installed chat agent is available on this machine.");
  return {
    argv: agent.run,
    task: `Implement GitHub issue ${issue.repository}#${issue.number}: ${issue.title}\n${issue.url}\n\nRead the issue requirements, implement the change in this worktree, and run the relevant tests.`,
  };
}

export function showIssueWorktree(machine, folder, chat) {
  const space = spaces().find((s) => s.folder === folder && (s.machine ?? null) === (machine ?? null));
  if (!space) return run("space.new", { folder, machine: machine ?? "", ...chat });
  if (chat) return run("tab.new", { space: space.id, folder, ...chat });
  return run("space.select", { id: space.id });
}

export async function issueWorktree(sp, repository, issue, root) {
  const context = await checkout(sp);
  if (context.repository.toLowerCase() !== repository.toLowerCase())
    throw new Error("The checkout repository changed. Refresh Issues and try again.");
  const options = { cwd: sp.folder, on: sp.machine, timeout: 600_000 };
  const git = (args) => exec("git", args, options);
  const binding = `${issue.repository}#${issue.number}`;
  const trees = await output(git(["worktree", "list", "--porcelain", "-z"]));
  const checkedOut = new Map();
  for (const record of trees.split("\0\0")) {
    const fields = record.split("\0");
    const path = fields[0].slice("worktree ".length);
    const ref = fields.find((field) => field.startsWith("branch refs/heads/"));
    if (ref) checkedOut.set(ref.slice("branch refs/heads/".length), path);
  }

  // The binding also finds the checkout after an issue title changes.
  const bindings = await git(["config", "--get-regexp", "^branch\\..*\\.herdr-github-issue$"]);
  if (bindings.code !== 1) {
    const lines = await output(bindings);
    for (const line of lines.split("\n")) {
      const match = /^branch\.(.+)\.herdr-github-issue (.+)$/.exec(line);
      if (match && match[2].toLowerCase() === binding.toLowerCase() && checkedOut.has(match[1]))
        return checkedOut.get(match[1]);
    }
  }

  const prefix = issue.repository.toLowerCase() === repository.toLowerCase()
    ? String(issue.number) : binding.toLowerCase().replace(/[/#]/g, "-");
  const title = issue.title.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "-");
  const suffix = [...title].slice(0, 48).join("").replace(/^-+|-+$/g, "");
  const branch = suffix ? `${prefix}-${suffix}` : prefix;
  const path = `${root.replace(/\/+$/, "")}/${repository}/${branch}`;
  const local = `refs/heads/${branch}`;
  const upstream = `refs/remotes/${context.remote}/${branch}`;
  const existing = await git(["show-ref", "--verify", "--quiet", local]);
  if (existing.code === 0) {
    const tracks = await output(git(["for-each-ref", "--format=%(upstream)", local]));
    if (tracks !== upstream) throw new Error(`Local branch ${branch} already exists with a different upstream.`);
  } else if (existing.code !== 1) throw new Error(existing.stderr || "Cannot check local branches.");

  // An explicit name lets gh reuse the issue's linked branch after a partial failure.
  await output(exec("gh", ["issue", "develop", issue.url, "--branch-repo", repository, "--name", branch]));
  if (!checkedOut.has(branch)) {
    if (existing.code === 0) await output(git(["worktree", "add", "--", path, branch]));
    else {
      await output(git(["fetch", "--no-tags", "--", context.remote, `refs/heads/${branch}:${upstream}`]));
      await output(git(["worktree", "add", "--track", "-b", branch, "--", path, upstream]));
    }
  }
  await output(git(["config", "--local", `branch.${branch}.herdr-github-issue`, binding]));
  return checkedOut.get(branch) ?? await output(git(["-C", path, "rev-parse", "--show-toplevel"]));
}
