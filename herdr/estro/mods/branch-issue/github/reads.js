import { exec } from "herdr";

const OWNER = "[a-z0-9](?:[a-z0-9-]*[a-z0-9])?";
const REPO = `${OWNER}/[a-z0-9_.-]+`;
const repositoryPattern = new RegExp(`^${REPO}$`, "i");
const remotePattern = new RegExp(
  `^(?:https?://(?:[^/@\\s]+@)?github\\.com/|ssh://(?:git@)?github\\.com(?::22)?/|git@github\\.com:)(${REPO})/?$`,
  "i",
);

function validRepository(value) {
  return typeof value === "string" && value.trim() === value &&
    repositoryPattern.test(value) && !/\/\.{1,2}$/.test(value);
}

function repositoryFromRemote(url) {
  const repository = remotePattern.exec(url.trim())?.[1].replace(/\.git$/i, "");
  return validRepository(repository) ? repository : null;
}

const validNumber = (number) => Number.isSafeInteger(number) && number > 0;
const keyOf = (repository, number) => `${repository.toLowerCase()}#${number}`;

function issueItem(repository, issue) {
  if (!validRepository(repository) || !validNumber(issue?.number) || typeof issue.title !== "string")
    throw new Error("GitHub returned invalid issue data.");
  return {
    number: issue.number,
    title: issue.title,
    url: `https://github.com/${repository}/issues/${issue.number}`,
    repository,
  };
}

async function ghApi(args, { missingOK = false, lines = false } = {}) {
  let result;
  try {
    // Never run gh in the checkout: remote paths and GitHub credentials live on different machines.
    result = await exec("gh", ["api", "--hostname", "github.com", ...args]);
  } catch (e) {
    if (/ENOENT|not found|no such file/i.test(e.message))
      throw new Error("Install GitHub CLI (gh) on this computer to read GitHub issues.");
    throw new Error("Could not run GitHub CLI on this computer.");
  }
  if (result.code !== 0) {
    const message = `${result.stderr ?? ""}\n${result.stdout ?? ""}`;
    if (result.code === 127)
      throw new Error("Install GitHub CLI (gh) on this computer to read GitHub issues.");
    if (result.code === 4 || /gh auth login|HTTP 401|bad credentials/i.test(message))
      throw new Error("GitHub CLI is not authenticated on this computer. Run gh auth login or check GH_TOKEN.");
    if (missingOK && /\(HTTP (?:404|410)\)/.test(message)) return null;
    throw new Error("GitHub request failed. Check your connection and repository access.");
  }
  try {
    return lines
      ? result.stdout.split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line))
      : JSON.parse(result.stdout);
  } catch {
    throw new Error("GitHub returned invalid JSON.");
  }
}

function graphPages(pages, connection) {
  if (!Array.isArray(pages) || !pages.length)
    throw new Error("GitHub returned invalid PR data.");
  return pages.flatMap((page) => {
    const nodes = connection(page?.data?.repository)?.nodes;
    if (page?.errors?.length || !Array.isArray(nodes))
      throw new Error("GitHub returned incomplete PR data.");
    return nodes;
  });
}

const PR_HEADS = `query($owner:String!,$name:String!,$branch:String!,$endCursor:String){
  repository(owner:$owner,name:$name){
    pullRequests(headRefName:$branch,first:100,after:$endCursor){
      nodes{number state headRefName headRefOid headRepository{nameWithOwner}}
      pageInfo{hasNextPage endCursor}
    }
  }
}`;
const CLOSING_ISSUES = `query($owner:String!,$name:String!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      closingIssuesReferences(first:100,after:$endCursor){
        nodes{number title repository{nameWithOwner}}
        pageInfo{hasNextPage endCursor}
      }
    }
  }
}`;

function graph(repository, query, fields) {
  const [owner, name] = repository.split("/");
  return ghApi(["graphql", "--paginate", "--slurp", "-f", `query=${query}`,
    "-f", `owner=${owner}`, "-f", `name=${name}`, ...fields]);
}

async function checkout(sp) {
  if (!sp?.folder) throw new Error("No Git checkout is selected.");
  const options = { cwd: sp.folder, on: sp.machine };
  const git = (args) => exec("git", args, options);
  const [remotes, head] = await Promise.all([
    git(["remote"]), git(["symbolic-ref", "--quiet", "HEAD"]),
  ]);
  if (remotes.code !== 0 || (head.code !== 0 && head.code !== 1))
    throw new Error("Cannot read the selected Git checkout.");
  const branch = head.code === 0 ? /^refs\/heads\/(.+)$/.exec(head.stdout.trim())?.[1] ?? "" : "";
  const config = async (name) => {
    if (!branch) return "";
    const result = await git(["config", "--get", `branch.${branch}.${name}`]);
    if (result.code !== 0 && result.code !== 1) throw new Error("Cannot read Git branch configuration.");
    return result.code === 0 ? result.stdout.trim() : "";
  };
  const names = remotes.stdout.trim().split(/\r?\n/).filter(Boolean);
  const [tracking, entries] = await Promise.all([
    config("remote"),
    Promise.all(names.map(async (name) => {
      const result = await git(["remote", "get-url", "--", name]);
      return [name, result.code === 0 ? repositoryFromRemote(result.stdout) : null];
    })),
  ]);
  const byName = new Map(entries);
  const repository = [tracking, "origin", "upstream", ...names].map((name) => byName.get(name)).find(Boolean);
  if (!repository) throw new Error("No supported github.com remote was found for this checkout.");
  const repositories = new Map(entries.filter(([, repo]) => repo).map(([, repo]) => [repo.toLowerCase(), repo]));
  return { branch, git, config, repository, repositories, trackingRepo: byName.get(tracking) };
}

async function branchPRs({ branch, git, config, trackingRepo, repositories }) {
  if (!branch) return [];
  const [head, merge, binding] = await Promise.all([
    git(["rev-parse", "--verify", "--quiet", "HEAD"]), config("merge"), config("herdr-pr"),
  ]);
  if (head.code !== 0 && head.code !== 1) throw new Error("Cannot read the Git checkout commit.");
  const sha = head.code === 0 ? head.stdout.trim() : "";
  const explicit = new RegExp(`^(${REPO})#([1-9][0-9]*)$`, "i").exec(binding);
  if (sha && explicit && validRepository(explicit[1]) && validNumber(Number(explicit[2]))) {
    const [, base, number] = explicit;
    const pr = await ghApi([`repos/${base}/pulls/${number}`], { missingOK: true });
    if (pr?.head?.sha === sha) return [{ base, number: Number(number) }];
  }
  const tracked = merge === `refs/heads/${branch}` ? trackingRepo?.toLowerCase() : null;
  if (!sha && !tracked) return [];
  const matches = (await Promise.all([...repositories.values()].map(async (base) => {
    const pages = await graph(base, PR_HEADS, ["-f", `branch=${branch}`]);
    return graphPages(pages, (repo) => repo?.pullRequests).flatMap((pr) => {
      const headRepo = pr?.headRepository?.nameWithOwner?.toLowerCase();
      if (pr?.headRefName !== branch || !validNumber(pr.number)) return [];
      const sameCommit = sha && pr.headRefOid === sha;
      const knownHead = tracked ? headRepo === tracked : repositories.has(headRepo);
      if (!knownHead || (!sameCommit && !(tracked && pr.state === "OPEN"))) return [];
      return [{ base, number: pr.number, headRepo }];
    });
  }))).flat();
  // If multiple configured forks share this ref and SHA, neither is proven to be the checkout's head.
  return new Set(matches.map((pr) => pr.headRepo)).size > 1 ? [] : matches;
}

async function closingIssues(context) {
  const prs = await branchPRs(context);
  return (await Promise.all(prs.map(async ({ base, number }) => {
    const pages = await graph(base, CLOSING_ISSUES, ["-F", `number=${number}`]);
    return graphPages(pages, (repo) => repo?.pullRequest?.closingIssuesReferences)
      .map((issue) => issueItem(issue?.repository?.nameWithOwner, issue));
  }))).flat();
}

async function openIssues(repository) {
  const rows = await ghApi([`repos/${repository}/issues`, "--method", "GET", "--paginate",
    "-f", "state=open", "-F", "per_page=100",
    "--jq", '.[] | select(has("pull_request") | not) | {number,title}'], { lines: true });
  return rows.map((issue) => issueItem(repository, issue));
}

async function branchIssues(branch, known) {
  const pattern = new RegExp(`(?:^|[/\\(])(${REPO})#([1-9][0-9]*)(?=$|[/_()\\-])`, "gi");
  const references = new Map();
  for (const [, repository, digits] of branch.matchAll(pattern)) {
    const number = Number(digits);
    if (validRepository(repository) && validNumber(number))
      references.set(keyOf(repository, number), { repository, number });
  }
  return (await Promise.all([...references].map(async ([key, { repository, number }]) => {
    if (known.has(key)) return known.get(key);
    const issue = await ghApi([`repos/${repository}/issues/${number}`], { missingOK: true });
    return issue && !issue.pull_request ? issueItem(repository, issue) : null;
  }))).filter(Boolean);
}

export async function readGitHubIssues(sp) {
  const context = await checkout(sp);
  const { repository, branch } = context;
  let linkedWarning;
  const readLinked = (promise) => promise.catch((error) => {
    linkedWarning ??= error.message;
    return [];
  });
  const [items, closing] = await Promise.all([openIssues(repository), readLinked(closingIssues(context))]);
  const known = new Map([...items, ...closing].map((issue) => [keyOf(issue.repository, issue.number), issue]));
  const explicit = await readLinked(branchIssues(branch, known));
  const linked = [...new Map([...explicit, ...closing].map((issue) => [keyOf(issue.repository, issue.number), issue])).values()];
  return linkedWarning ? { repository, items, linked, linkedWarning } : { repository, items, linked };
}
