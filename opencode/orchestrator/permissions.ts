/** The regular profile's query boundary; this is not an operating-system sandbox. */
export const readOnlyRoles = new Set([
  "build",
  "plan",
  "reviewer",
  "explore",
  "researcher",
]);

const writerRoles = new Set(["coder", "scribe"]);

/** Shared by native role permissions and the runtime query guard. */
export const mcpQueryTools = [
  "codegraph_codegraph_explore",
  "context7_resolve-library-id",
  "context7_query-docs",
  "context7_resolve_library_id",
  "context7_query_docs",
  "exa_web_search_exa",
  "exa_web_fetch_exa",
  "exa_get_code_context_exa",
  "gh_grep_searchGitHub",
] as const;

const queryTools = new Set([
  "read",
  "glob",
  "grep",
  "list",
  "skill",
  "webfetch",
  "websearch",
  "codesearch",
  "lsp",
  ...mcpQueryTools,
]);

interface Options {
  flags?: string;
  values?: string;
  optional?: string;
  numeric?: string;
  count?: boolean;
}

function denied(reason: string): never {
  throw new Error(`Read-only policy: ${reason}`);
}

/** One simple command, with quoting but no shell expansion or composition. */
function words(command: string): string[] {
  if (!command || /[\u0000-\u0008\u000a-\u001f\u007f]/.test(command)) {
    denied(
      "use separate tool calls for queries; shell operators, escapes and substitutions are unavailable",
    );
  }
  const result: string[] = [];
  let word = "";
  let quote = "";
  let started = false;
  for (const character of command) {
    if (quote) {
      if (character === quote) quote = "";
      else if (quote === '"' && /[`$\\]/.test(character))
        denied("use single quotes for literal substitutions or escapes");
      else word += character;
      continue;
    }
    if (character === '"' || character === "'") {
      quote = character;
      started = true;
    } else if (/\s/.test(character)) {
      if (started) result.push(word);
      word = "";
      started = false;
    } else {
      if (/[;&]/.test(character))
        denied(
          "command composition is unavailable; use separate tool calls for independent queries",
        );
      if (/[|<>]/.test(character))
        denied(
          "pipes and redirection are unavailable; use --jq or separate tool calls for queries. Saving or extracting artifacts belongs to coder with an owned destination",
        );
      if (/[;|&<>`$\\(){}\[\]*?!~#]/.test(character)) {
        denied("quote literal arguments; shell expansion is unavailable");
      }
      word += character;
      started = true;
    }
  }
  if (quote) denied("unterminated shell quote");
  if (started) result.push(word);
  if (!result.length) denied("empty command");
  return result;
}

function options(argv: string[], spec: Options): string[] {
  const flags = new Set(spec.flags?.split(" "));
  const values = new Set(spec.values?.split(" "));
  const optional = new Set(spec.optional?.split(" "));
  const positional: string[] = [];
  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index];
    if (argument === "--") return positional.concat(argv.slice(index + 1));
    if (!argument.startsWith("-") || argument === "-") {
      positional.push(argument);
      continue;
    }
    const equals = argument.indexOf("=");
    const name = equals < 0 ? argument : argument.slice(0, equals);
    if (flags.has(name) && equals < 0) continue;
    if (optional.has(name)) continue;
    if (spec.count && /^-[0-9]+$/.test(argument)) continue;
    if (values.has(name)) {
      if (equals >= 0) continue;
      if (++index >= argv.length) denied(`missing argument for ${name}`);
      continue;
    }
    if (
      spec.numeric &&
      new RegExp(`^-[${spec.numeric}][0-9]+$`).test(argument)
    ) {
      continue;
    }
    denied(`unsupported query option ${name}`);
  }
  return positional;
}

function prependOnce(prefix: string[], argv: string[]): string[] {
  return prefix.every((argument, index) => argv[index] === argument)
    ? argv
    : [...prefix, ...argv];
}

const diffFlags =
  "--stat --numstat --shortstat --name-only --name-status --check --summary --patch -p --no-patch -s --raw --binary --full-index --no-color --exit-code --quiet --no-renames --no-ext-diff --no-textconv --ignore-all-space -w --ignore-space-change -b --ignore-space-at-eol --ignore-blank-lines";
const diffValues = "--unified -U --diff-filter --src-prefix --dst-prefix";
const logFlags =
  "--oneline --graph --all --first-parent --no-merges --merges --reverse --date-order --topo-order --boundary --no-notes --use-mailmap";
const logValues =
  "--format --pretty --max-count -n --skip --since --until --after --before --author --committer --grep --date --encoding";

const gitQueries: Record<string, Options> = {
  status: {
    flags: "--short -s --branch -b --show-stash --no-renames -z",
    optional: "--porcelain --untracked-files -u --ignore-submodules",
  },
  diff: {
    flags: `${diffFlags} --cached --staged`,
    values: diffValues,
    optional: "--relative --find-renames --find-copies --color",
    numeric: "U",
  },
  log: {
    flags: `${diffFlags} ${logFlags}`,
    values: `${diffValues} ${logValues}`,
    optional: "--decorate --color --find-renames --find-copies",
    numeric: "nU",
    count: true,
  },
  show: {
    flags: `${diffFlags} ${logFlags}`,
    values: `${diffValues} ${logValues}`,
    optional: "--decorate --color --find-renames --find-copies",
    numeric: "nU",
    count: true,
  },
  "rev-list": {
    flags:
      "--count --left-right --left-only --right-only --parents --children --all --first-parent --no-merges --merges --reverse --boundary --cherry-pick --cherry-mark",
    values: "--max-count -n --skip --since --until --min-parents --max-parents",
    numeric: "n",
    count: true,
  },
  grep: {
    flags:
      "--no-textconv -n --line-number -i --ignore-case -F --fixed-strings -E --extended-regexp -G --basic-regexp -P --perl-regexp -w --word-regexp -l --files-with-matches -L --files-without-match -c --count -h --no-filename -H --with-filename --cached --untracked --no-index --no-color --full-name",
    values:
      "-e -f -A -B -C --after-context --before-context --context --max-depth",
    numeric: "ABC",
  },
  blame: {
    flags:
      "--no-textconv --line-porcelain --porcelain -p --incremental --show-name -f --show-number -n --show-email -e --root --first-parent -w",
    values: "-L --date --ignore-rev --abbrev",
  },
  "rev-parse": {
    flags:
      "--verify --quiet -q --show-toplevel --git-dir --absolute-git-dir --git-common-dir --is-inside-work-tree --is-bare-repository --show-prefix --symbolic --symbolic-full-name --end-of-options",
    values: "--git-path",
    optional: "--abbrev-ref --short",
  },
  "ls-files": {
    flags:
      "--cached -c --deleted -d --modified -m --others -o --ignored -i --stage -s --unmerged -u --exclude-standard --full-name -z --error-unmatch",
    values: "--exclude -x --exclude-from -X",
  },
  "ls-tree": {
    flags:
      "-r -t -d -l --long --name-only --name-status -z --full-tree --full-name",
  },
  "merge-base": {
    flags: "--all -a --is-ancestor --octopus --independent --fork-point",
  },
};

function safeGit(argv: string[]): string[] {
  const prefix: string[] = [];
  let index = 0;
  while (argv[index]?.startsWith("-")) {
    const flag = argv[index++];
    if (flag === "-C") {
      if (!argv[index]) denied("git -C requires a directory");
      prefix.push(flag, argv[index++]);
    } else if (flag === "--no-pager" || flag === "--no-optional-locks") {
      // These are supplied once in the normalized invocation.
    } else if (flag === "-c" && argv[index] === "core.fsmonitor=false") {
      index++;
    } else {
      denied("git global options may not configure programs or aliases");
    }
  }
  const query = argv[index++];
  const safety = [
    "--no-pager",
    "--no-optional-locks",
    "-c",
    "core.fsmonitor=false",
  ];
  if (query === "branch") {
    const args = argv.slice(index);
    if (args.length === 1 && args[0] === "--show-current")
      return ["git", ...safety, ...prefix, query, ...args];
    const positional = options(args, {
      flags: "--list --all -a --remotes -r --no-color --verbose -v -vv",
      values: "--format --sort",
    });
    if (
      positional.length &&
      !args
        .slice(0, args.indexOf("--") < 0 ? args.length : args.indexOf("--"))
        .includes("--list")
    )
      denied(
        "branch inspection requires --list before name filters; branch creation and mutation belong to coder",
      );
    return [
      "git",
      ...safety,
      ...prefix,
      query,
      ...prependOnce(["--list"], args),
    ];
  }
  if (query === "ls-remote")
    denied(
      "remote transports may execute configured helpers; inspect remote refs with gh/glab GET queries or ask the root to assign the command to coder",
    );
  if (query === "remote") {
    const args = argv.slice(index);
    if (
      args.length &&
      !(args.length === 1 && ["-v", "--verbose"].includes(args[0]))
    ) {
      if (
        args[0] !== "get-url" ||
        options(args.slice(1), { flags: "--push --all" }).length !== 1
      )
        denied(
          "remote inspection accepts only remote, remote -v, or remote get-url NAME",
        );
    }
    return ["git", ...safety, ...prefix, query, ...args];
  }
  if (!Object.hasOwn(gitQueries, query))
    denied("git command is not an approved inspection");
  const spec = gitQueries[query];
  const args = argv.slice(index);
  options(args, spec);
  if (["diff", "log", "show"].includes(query)) {
    return [
      "git",
      ...safety,
      ...prefix,
      query,
      ...prependOnce(["--no-ext-diff", "--no-textconv"], args),
    ];
  }
  if (query === "blame" || query === "grep") {
    return [
      "git",
      ...safety,
      ...prefix,
      query,
      ...prependOnce(["--no-textconv"], args),
    ];
  }
  return ["git", ...safety, ...prefix, query, ...args];
}

const githubQueries = new Set([
  "pr view",
  "pr list",
  "pr diff",
  "pr checks",
  "issue view",
  "issue list",
  "repo view",
  "run view",
  "run list",
  "search issues",
  "search prs",
  "search repos",
  "search code",
  "search commits",
]);
const gitlabQueries = new Set([
  "mr view",
  "mr list",
  "mr diff",
  "issue view",
  "issue list",
  "repo view",
  "ci list",
]);

function safeApi(program: string, args: string[]): void {
  const positional = options(args, {
    flags: "--paginate --slurp --include -i --silent",
    values: `--method -X --jq -q --hostname --header -H${program === "glab" ? " --output" : ""}`,
  });
  for (let index = 0; index < args.length; index++) {
    if (args[index] === "--") break;
    const [name] = args[index].split("=");
    if (
      ![
        "--method",
        "-X",
        "--jq",
        "-q",
        "--hostname",
        "--header",
        "-H",
        "--output",
      ].includes(name)
    )
      continue;
    const value = args[index].includes("=")
      ? args[index].slice(name.length + 1)
      : args[++index];
    if (["--method", "-X"].includes(name) && value !== "GET")
      denied("API calls must use GET");
    if (name === "--output" && !["json", "ndjson"].includes(value))
      denied(
        "glab API --output accepts json or ndjson formatting, not a file destination",
      );
    if (
      ["--header", "-H"].includes(name) &&
      !/^Accept:[ \t]*[a-zA-Z0-9!#$&^_.+*/;=, \t-]+$/i.test(value)
    )
      denied("API queries accept only a literal Accept representation header");
  }
  if (positional.length !== 1)
    denied(
      `API query requires one explicit endpoint; use ${program} help api for usage`,
    );
  const endpoint = positional[0].replace(/^\//, "");
  const path = endpoint.split("?")[0];
  if (path.includes("..") || !/^[a-zA-Z0-9_./%:@-]+$/.test(path)) {
    denied("unsupported API endpoint");
  }
  const approved =
    program === "gh"
      ? /^(repos\/[^/]+\/[^/]+(\/(issues|pulls|commits|compare|contents|git|actions|branches|tags|releases|milestones|labels)(\/.*)?)?|search\/(issues|code|commits|repositories))$/.test(
          path,
        )
      : /^projects\/[^/]+(\/(issues|merge_requests|repository|pipelines|jobs|releases|labels|milestones)(\/.*)?)?$/.test(
          path,
        );
  if (!approved) denied("API endpoint is not an approved tracker query");
}

function safeTracker(program: string, argv: string[]): string[] {
  const queries = program === "gh" ? githubQueries : gitlabQueries;
  const help =
    argv[0] === "help"
      ? argv.slice(1)
      : ["--help", "-h"].includes(argv.at(-1) ?? "")
        ? argv.slice(0, -1)
        : undefined;
  if (help) {
    const topics = new Set([
      "api",
      "release",
      "environment",
      "formatting",
      "exit-codes",
      "reference",
      ...Array.from(queries, (query) => query.split(" ")[0]),
    ]);
    if (
      help.some((word) => !/^[a-z][a-z0-9-]*$/.test(word)) ||
      (help.length && !topics.has(help[0]))
    )
      denied(
        "help accepts literal built-in tracker topics without execution arguments or flags",
      );
    // Canonical help never invokes the documented operation or a custom alias/extension.
    return [program, "help", ...help];
  }
  const query = argv.slice(0, 2).join(" ");
  if (["run download", "release download", "ci artifact"].includes(query))
    denied(
      "artifact download/extraction writes local files; the root assigns it to coder with an owned destination, preferably in existing relevant work",
    );
  if (argv[0] === "api") {
    safeApi(program, argv.slice(1));
  } else {
    if (!queries.has(query)) {
      denied("tracker command is not an approved query");
    }
    options(argv.slice(2), {
      flags:
        "--comments --commits --files --patch --name-only --watch=false --checks --log --log-failed --verbose --all --closed --opened --merged --draft --ready --no-color",
      values:
        "--repo -R --json --jq -q --limit -L --state -s --label -l --author --assignee -a --search -S --base -B --head -H --branch -b --workflow -w --event -e --status --job -j --page --per-page -P --output -F --sort --order --owner --language --filename --extension --match" +
        (program === "glab" ? " --source-branch --target-branch" : ""),
    });
  }
  return [program, ...argv];
}

const fileQueries: Record<string, Options> = {
  pwd: { flags: "-L -P" },
  ls: { flags: "-a -A -l -la -al -lah -alh -h -d -F -G -n -p -R -r -S -t -1" },
  cat: { flags: "-b -e -n -s -t -u -v" },
  head: { flags: "-q -v", values: "-n -c", numeric: "0123456789" },
  tail: { flags: "-q -v", values: "-n -c" },
  wc: { flags: "-c -l -m -w" },
  rg: {
    flags:
      "--no-config --files --hidden --no-ignore --no-ignore-vcs --line-number -n --files-with-matches -l --files-without-match --ignore-case -i --smart-case -S --fixed-strings -F --word-regexp -w --line-regexp -x --count -c --count-matches --only-matching -o --quiet -q --no-heading --heading --with-filename -H --no-filename -I --no-messages --pcre2 -P --multiline -U --stats",
    values:
      "--regexp -e --glob -g --iglob --type -t --type-not -T --after-context -A --before-context -B --context -C --max-count -m --max-depth --max-filesize --sort --sortr --encoding",
    numeric: "ABCm",
  },
};

function quote(argument: string): string {
  return `'${argument.replaceAll("'", "'\"'\"'")}'`;
}

const queryEnvironment: Record<string, string[]> = {
  git: ["GIT_NO_LAZY_FETCH=1"],
  gh: ["PAGER=cat", "GH_PAGER=cat", "GLAB_PAGER=cat"],
  glab: ["PAGER=cat", "GH_PAGER=cat", "GLAB_PAGER=cat"],
};

function safeCommand(command: string): string {
  const tokens = words(command);
  let index = 0;
  while (/^[a-zA-Z_][a-zA-Z0-9_]*=/.test(tokens[index] ?? "")) index++;
  const [program, ...argv] = tokens.slice(index);
  const environment = Object.hasOwn(queryEnvironment, program)
    ? queryEnvironment[program]
    : [];
  // Accept only known safety values, regardless of order or omitted assignments.
  // Always emit the complete environment and revalidate the executable/arguments.
  if (
    !tokens
      .slice(0, index)
      .every((assignment) => environment.includes(assignment))
  )
    denied(
      "environment assignments must match the query's approved safety values",
    );
  let normalized: string[];
  if (program === "command") {
    if (
      argv.length !== 2 ||
      argv[0] !== "-v" ||
      !/^[a-zA-Z0-9][a-zA-Z0-9._+-]*$/.test(argv[1])
    )
      denied(
        "CLI discovery accepts command -v NAME with one literal executable name",
      );
    normalized = [program, ...argv];
  } else if (program === "git") normalized = safeGit(argv);
  else if (program === "gh" || program === "glab")
    normalized = safeTracker(program, argv);
  else {
    if (!Object.hasOwn(fileQueries, program))
      denied(
        "executable is not an approved query; use read/glob/grep for files. Project scripts and verification belong to coder via the root; do not retry with shell wrappers or alternate spellings",
      );
    const spec = fileQueries[program];
    options(argv, spec);
    normalized = [
      program,
      ...(program === "rg" ? prependOnce(["--no-config"], argv) : argv),
    ];
  }
  // The CLIs can otherwise launch a user-configured pager despite read-only arguments.
  return [...environment, ...normalized.map(quote)].join(" ");
}

/**
 * Throws before an unsupported tool executes. Pass the actual mutable tool args:
 * accepted shell queries are normalized to disable configured Git programs/pagers.
 * The caller owns authorization of orchestration and memory tools separately.
 */
export function assertReadOnlyTool(
  role: string,
  tool: string,
  args: Record<string, unknown>,
): void {
  if (writerRoles.has(role)) return;
  if (!readOnlyRoles.has(role))
    denied("unknown agent has no implicit tool access");
  if (tool === "bash") {
    if (typeof args.command !== "string")
      denied("bash requires a command string");
    args.command = safeCommand(args.command);
    return;
  }
  if (!queryTools.has(tool)) denied(`${role} cannot execute ${tool}`);
  if (
    tool === "lsp" &&
    ![
      "goToDefinition",
      "findReferences",
      "hover",
      "documentSymbol",
      "workspaceSymbol",
      "goToImplementation",
      "prepareCallHierarchy",
      "incomingCalls",
      "outgoingCalls",
    ].includes(String(args.operation))
  )
    denied("LSP permits navigation and symbol queries only");
  if (
    args.method !== undefined &&
    !["GET", "HEAD"].includes(String(args.method))
  ) {
    denied("query tools cannot change HTTP methods");
  }
  if (args.body !== undefined || args.headers !== undefined) {
    denied("query tools cannot supply request bodies or headers");
  }
}
