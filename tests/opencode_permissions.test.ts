import { describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { rolePermissions } from "../opencode/orchestrator/prompts";
import {
  assertReadOnlyTool,
  guardBash,
  mcpQueryTools,
  readOnlyRoles,
} from "../opencode/orchestrator/permissions";

function query(command: string, role = "reviewer"): string {
  const args = { command };
  assertReadOnlyTool(role, "bash", args);
  return args.command;
}

describe("regular read-only tool boundary", () => {
  test("read-only roles can discover MCP resources and read a discovered URI", () => {
    for (const role of readOnlyRoles) {
      // Native MCP resource tools use the read permission, not a server tool name.
      expect(rolePermissions(role).read).toBe("allow");
      for (const [tool, args] of [
        ["list_mcp_resources", {}],
        ["list_mcp_resources", { server: "project" }],
        ["list_mcp_resource_templates", {}],
        ["list_mcp_resource_templates", { server: "project" }],
        ["read_mcp_resource", { server: "project", uri: "fixture://guide" }],
      ] as const)
        expect(() => assertReadOnlyTool(role, tool, args)).not.toThrow();
      expect(() =>
        assertReadOnlyTool(role, "project_update_issue", {}),
      ).toThrow("Read-only policy:");
    }
  });

  test("tracker help is available without executing the documented operation", () => {
    for (const command of [
      "PAGER=cat GH_PAGER=cat 'gh' 'help' 'api'",
      "gh api --help",
      "gh --help",
      "gh help formatting",
      "gh pr view -h",
      "gh run download --help",
      "gh help run download",
      "glab help api",
      "glab api --help",
      "glab ci artifact --help",
      "glab help",
    ]) {
      for (const role of readOnlyRoles) {
        const normalized = query(command, role);
        expect(query(normalized, role)).toBe(normalized);
      }
    }
  });

  test("help cannot authorize aliases, extensions, execution flags or shell composition", () => {
    for (const command of [
      "gh custom-alias --help",
      "glab custom-extension --help",
      "gh extension exec custom --help",
      "gh help api --web",
      "gh help api --method POST",
      "gh run download -- --help",
      "gh help 'api; touch marker'",
      "gh api --help; touch marker",
      "glab api --help | tee marker",
      "gh help api > marker",
      "gh help api --jq 'env'",
    ]) {
      for (const role of readOnlyRoles)
        expect(() => query(command, role), command).toThrow(
          "Read-only policy:",
        );
    }
    expect(query("gh run download 123 --dir artifacts", "coder")).toBe(
      "gh run download 123 --dir artifacts",
    );
  });

  test("shell composition and artifact writes explain the supported next action", () => {
    for (const role of readOnlyRoles) {
      expect(() => query("git remote -v; command -v gh", role)).toThrow(
        "separate tool calls",
      );
      expect(() =>
        query(
          "gh api repos/example/project/actions/artifacts/123/zip | tee /tmp/artifact.zip | wc -c",
          role,
        ),
      ).toThrow("coder");
      expect(() =>
        query("gh run download 123 --dir /tmp/artifacts", role),
      ).toThrow("coder");
      expect(() => query("gh api", role)).toThrow("gh help api");
    }
  });

  test("common Git inspections and CLI discovery stay normalized and read-only", () => {
    for (const command of [
      "git log -1",
      "git log -5 --oneline",
      "git log -10",
      "git log -30",
      "git rev-list --left-right --count main...origin/main",
      "git rev-list --parents -n 1 HEAD",
      "git branch --show-current",
      "git branch --all --no-color",
      "git branch --list 'feature/*' --all",
      "glab mr list --source-branch feature/example --target-branch main --all",
      "glab api projects/123/merge_requests/1/discussions --paginate --output ndjson",
      "git grep -n needle HEAD -- src",
      "git show --find-renames HEAD",
      "git worktree list",
      "git worktree list --porcelain",
      "git reflog",
      "git reflog show main",
      "git reflog --format='%h %gd %gs' -10",
      "git reflog --all --date=iso --since='2026-01-01'",
      "git show-ref",
      "git show-ref --heads --dereference",
      "git show-ref --verify --quiet refs/heads/main",
      ...["docker", "mise", "colima", "multipass", "sh"].map(
        (cli) => `command -v ${cli}`,
      ),
    ]) {
      for (const role of readOnlyRoles) {
        const normalized = query(command, role);
        expect(query(normalized, role)).toBe(normalized);
      }
    }
  });

  test("branch listing cannot create branches and API formatting cannot write files", () => {
    for (const command of [
      "git branch feature/new",
      "git branch --all feature/new",
      "git branch -D feature/old",
      "git branch --list --force feature/new",
      "git worktree add ../elsewhere main",
      "git worktree remove ../elsewhere",
      "git worktree prune",
      "git reflog expire --expire=now --all",
      "git reflog delete main@{0}",
      "glab api projects/123 --output /tmp/output.json",
      "glab api projects/123 --output ndjson --method POST",
      "gh api repos/example/project --output ndjson",
    ])
      expect(() => query(command), command).toThrow("Read-only policy:");
  });

  test("quoted API filters and Accept headers arrive as literal arguments", () => {
    const directory = mkdtempSync(join(tmpdir(), "opencode-quoted-api-"));
    try {
      writeFileSync(
        join(directory, "gh"),
        "#!/bin/sh\nprintf '%s\\n' \"$@\"\n",
        { mode: 0o755 },
      );
      const filter = '.files[] | select(.filename == "literal") | .patch';
      const command = `gh api repos/example/project/pulls/1 --jq '${filter}' -H 'Accept: application/vnd.github+json'`;
      const normalized = query(command);
      expect(query(normalized)).toBe(normalized);
      const result = Bun.spawnSync(["/bin/sh", "-c", normalized], {
        env: { PATH: directory },
      });
      expect(result.exitCode).toBe(0);
      expect(result.stdout.toString().trim().split("\n")).toEqual([
        "api",
        "repos/example/project/pulls/1",
        "--jq",
        filter,
        "-H",
        "Accept: application/vnd.github+json",
      ]);
      for (const header of [
        "--header 'Accept: application/vnd.github.diff'",
        "--header='Accept: application/json'",
      ]) {
        expect(() =>
          query(`gh api repos/example/project/pulls/1 ${header}`),
        ).not.toThrow();
      }
      for (const literal of [
        "'a; b & c > d'",
        "'$(touch forbidden)'",
        "'literal `command`'",
        "'\\.literal'",
      ]) {
        const safe = query(`rg -F ${literal} README.md`);
        expect(query(safe)).toBe(safe);
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
  test("read-only roles can fetch documentation through Exa", () => {
    for (const role of readOnlyRoles) {
      expect(() =>
        assertReadOnlyTool(role, "exa_web_fetch_exa", {
          urls: [
            "https://www.postgresql.org/docs/current/functions-admin.html",
          ],
          maxCharacters: 6000,
        }),
      ).not.toThrow();
    }
  });

  test("native MCP permissions and the argument guard share approved queries", () => {
    for (const role of [...readOnlyRoles, "coder", "scribe"]) {
      const permissions = rolePermissions(role);
      const exposed = Object.keys(permissions).filter((name) =>
        /^(codegraph|context7|exa|gh_grep)_/.test(name),
      );
      expect(exposed.sort()).toEqual([...mcpQueryTools].sort());
      for (const name of exposed) {
        expect(permissions[name]).toBe("allow");
        expect(() => assertReadOnlyTool(role, name, {})).not.toThrow();
      }
      for (const name of [
        "exa_agent_run",
        "exa_unknown_read",
        "context7_execute",
        "gh_grep_delete",
        "codegraph_init",
        "codegraph_unknown_read",
      ]) {
        expect(permissions[name] ?? permissions["*"]).toBe("deny");
        if (readOnlyRoles.has(role))
          expect(() => assertReadOnlyTool(role, name, {})).toThrow(
            "Read-only policy:",
          );
      }
    }
    for (const args of [
      { method: "POST" },
      { body: "mutation" },
      { headers: {} },
    ])
      expect(() =>
        assertReadOnlyTool("build", "exa_web_fetch_exa", args),
      ).toThrow("Read-only policy:");
  });

  test("a project MCP allowlist never widens what a read-only role may call", () => {
    const mcp = { tracker: { enabled: true } };
    for (const role of readOnlyRoles) {
      const permissions = rolePermissions(role, mcp, { "tracker_*": "allow" });
      for (const name of [
        "tracker_get_issue",
        "tracker_list_issues",
        "tracker_save_issue",
        "tracker_unknown_read",
      ]) {
        expect(permissions[name] ?? permissions["*"], role).toBe("deny");
        expect(() => assertReadOnlyTool(role, name, {}), role).toThrow(
          "Read-only policy:",
        );
      }
    }
    expect(
      rolePermissions("coder", mcp, { "tracker_*": "allow" })["tracker_*"],
    ).toBe("allow");
  });

  test("LSP exposes navigation to every role while read-only roles reject other operations", () => {
    for (const role of [
      "build",
      "plan",
      "coder",
      "scribe",
      "reviewer",
      "explore",
      "researcher",
    ])
      expect(rolePermissions(role).lsp).toBe("allow");
    for (const role of ["build", "plan", "reviewer", "explore", "researcher"]) {
      for (const operation of [
        "goToDefinition",
        "findReferences",
        "hover",
        "documentSymbol",
        "workspaceSymbol",
        "goToImplementation",
        "prepareCallHierarchy",
        "incomingCalls",
        "outgoingCalls",
      ])
        expect(() =>
          assertReadOnlyTool(role, "lsp", {
            operation,
            filePath: "src/app.ts",
            line: 1,
            character: 1,
          }),
        ).not.toThrow();
      for (const operation of ["rename", "executeCommand", "format", undefined])
        expect(() => assertReadOnlyTool(role, "lsp", { operation })).toThrow(
          "LSP permits navigation",
        );
    }
  });

  test("queries remain valid when their normalized commands are checked again", () => {
    for (const command of [
      "git rev-parse origin/topic-branch",
      "git -C '/tmp/repo with spaces' remote get-url origin",
      "git diff --stat",
      "git diff --src-prefix --no-ext-diff -- README.md",
      "git log --format=--no-textconv -n1",
      "git show HEAD -- --no-textconv",
      "git blame README.md",
      "gh api repos/example/project/pulls/12/comments --paginate",
      "glab api projects/example%2Fproject/merge_requests/12",
      "rg -n needle README.md",
      "rg -e --no-config README.md",
      "rg --files -g '*.ts'",
      `rg -F "someone's name" README.md`,
    ]) {
      const normalized = query(command);
      for (const role of readOnlyRoles) {
        expect(query(normalized, role), command).toBe(normalized);
      }
    }
  });

  test("partial and reordered safe pager assignments normalize to the same tracker query", () => {
    for (const [program, endpoint] of [
      ["gh", "repos/example/project/pulls/12/comments"],
      ["glab", "projects/example%2Fproject/merge_requests/12/notes"],
    ]) {
      const command = `'${program}' 'api' '${endpoint}'`;
      const expected = query(command);
      for (const prefix of [
        "PAGER=cat GH_PAGER=cat",
        "PAGER=cat GLAB_PAGER=cat",
        "GH_PAGER=cat PAGER=cat",
        "GLAB_PAGER=cat GH_PAGER=cat PAGER=cat",
        "PAGER=cat",
        "GH_PAGER=cat",
        "GLAB_PAGER=cat",
        "PAGER=cat PAGER=cat",
      ]) {
        for (const role of readOnlyRoles) {
          const normalized = query(`${prefix} ${command}`, role);
          expect(normalized).toBe(expected);
          expect(query(normalized, role)).toBe(expected);
        }
      }
    }
  });

  test("partial tracker prefixes still disable every configured pager at execution", () => {
    const directory = mkdtempSync(join(tmpdir(), "opencode-tracker-query-"));
    try {
      for (const program of ["gh", "glab"]) {
        writeFileSync(
          join(directory, program),
          '#!/bin/sh\nprintf "%s\\n" "$PAGER" "$GH_PAGER" "$GLAB_PAGER" "$@"\n',
          { mode: 0o755 },
        );
        const endpoint =
          program === "gh"
            ? "repos/example/project/pulls/12/comments"
            : "projects/12/merge_requests/34/notes";
        const command = `PAGER=cat ${program === "gh" ? "GH" : "GLAB"}_PAGER=cat '${program}' 'api' '${endpoint}'`;
        const result = Bun.spawnSync(["/bin/sh", "-c", query(command)], {
          env: {
            PATH: directory,
            PAGER: "/unexpected-pager",
            GH_PAGER: "/unexpected-pager",
            GLAB_PAGER: "/unexpected-pager",
          },
        });
        expect(result.exitCode, result.stderr.toString()).toBe(0);
        expect(result.stdout.toString()).toBe(
          `cat\ncat\ncat\napi\n${endpoint}\n`,
        );
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  test("safety prefixes do not authorize mutations or arbitrary environments", () => {
    for (const command of [
      "GIT_NO_LAZY_FETCH=1 git reset --hard",
      "GIT_NO_LAZY_FETCH=1 git -c core.fsmonitor=/tmp/unsafe status",
      "GIT_NO_LAZY_FETCH=1 git diff --ext-diff",
      "GIT_NO_LAZY_FETCH=0 git status",
      "GIT_NO_LAZY_FETCH=1 GH_PAGER=cat git status",
      "GIT_NO_LAZY_FETCH=1 sh -c 'git status'",
      "PAGER=cat GH_PAGER=cat GLAB_PAGER=cat gh api repos/o/r/issues/1 -X DELETE",
      "PAGER=cat GH_PAGER=cat GLAB_PAGER=cat glab mr checkout 12",
      "PAGER=cat GH_PAGER=cat GLAB_PAGER=cat git status",
      "PAGER=sh GH_PAGER=cat GLAB_PAGER=cat gh pr list",
      "PAGER=cat GH_PAGER=sh GLAB_PAGER=cat gh pr list",
      "PAGER=cat GH_PAGER=cat GLAB_PAGER=sh glab mr list",
      "PAGER=cat GH_PAGER=cat gh api repos/o/r/issues/1 -X DELETE",
      "PAGER=cat GLAB_PAGER=cat glab mr checkout 12",
      "GH_PAGER=cat PAGER=sh gh pr list",
      "PAGER=sh PAGER=cat gh pr list",
      "PAGER=cat PAGER=sh gh pr list",
      "PAGER='cat -n' gh pr list",
      "PATH=/tmp PAGER=cat gh pr list",
      "PAGER=cat sh -c 'gh pr list'",
      "PAGER=cat constructor",
      "PAGER=cat",
      "PAGER=cat GH_PAGER=cat GLAB_PAGER=cat GH_HOST=example.invalid gh pr list",
      "PAGER=cat GH_PAGER=cat GLAB_PAGER=cat gh pr list; touch /tmp/unsafe",
      "rg --no-config --pre sh needle README.md",
    ]) {
      for (const role of readOnlyRoles)
        expect(() => query(command, role), command).toThrow(
          "Read-only policy:",
        );
    }
  });

  test("project scripts require coder even when named as inspections", () => {
    for (const command of ["bun docs list", "npm run docs", "npx docs list"]) {
      for (const role of readOnlyRoles)
        expect(() => query(command, role)).toThrow(
          "Project scripts and verification belong to coder via the root",
        );
      expect(query(command, "coder")).toBe(command);
    }
  });

  test("CLI discovery reports availability without executing the CLI", () => {
    const directory = mkdtempSync(join(tmpdir(), "opencode-cli-discovery-"));
    const marker = join(directory, "executed");
    try {
      for (const cli of [
        "gh",
        "glab",
        "docker",
        "mise",
        "colima",
        "multipass",
      ]) {
        const binary = join(directory, cli);
        writeFileSync(binary, '#!/bin/sh\ntouch "$MARKER"\n', { mode: 0o755 });
        for (const role of readOnlyRoles) {
          const result = Bun.spawnSync(
            ["/bin/sh", "-c", query(`command -v ${cli}`, role)],
            {
              env: { PATH: directory, MARKER: marker },
            },
          );
          expect(result.exitCode).toBe(0);
          expect(result.stdout.toString().trim()).toBe(binary);
          expect(existsSync(marker)).toBe(false);
        }
        rmSync(binary);
        expect(
          Bun.spawnSync(["/bin/sh", "-c", query(`command -v ${cli}`)], {
            env: { PATH: directory },
          }).exitCode,
        ).not.toBe(0);
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  test("projects opt coder into configured MCP tools without broadening native or reader access", () => {
    const mcp = {
      project: { type: "remote", url: "https://example.invalid/mcp" },
    };
    const global = {
      "project_*": "allow",
      "unknown_*": "allow",
      task: "allow",
      "*": "allow",
    };
    const agent = { project_delete_item: "deny" };
    const coder = rolePermissions("coder", mcp, global, agent);
    expect(coder["project_*"]).toBe("allow");
    expect(coder.project_delete_item).toBe("deny");
    expect(coder["unknown_*"]).toBeUndefined();
    expect(coder["*"]).toBe("deny");
    expect(coder.task).toBe("deny");
    expect(rolePermissions("coder", mcp)["project_*"]).toBeUndefined();
    for (const role of [...readOnlyRoles, "scribe"]) {
      expect(
        rolePermissions(role, mcp, global, agent)["project_*"],
      ).toBeUndefined();
    }
  });

  test("every read-only role can inspect the checkout and tracker", () => {
    for (const role of readOnlyRoles) {
      expect(query("git status --short --branch", role)).toContain("'status'");
      expect(query("git rev-parse HEAD", role)).toContain("'rev-parse'");
      expect(query("git diff --stat", role)).toContain("'--no-ext-diff'");
      expect(query("gh pr view 12 --json number,title", role)).toContain(
        "'pr' 'view'",
      );
      expect(query("gh issue list --state open --limit 10", role)).toContain(
        "'issue' 'list'",
      );
    }
  });

  test("Git inspections disable optional writes and configured external programs", () => {
    for (const command of [
      "git status",
      "git diff HEAD",
      "git show HEAD",
      "git log -n5",
      "git blame file.ts",
    ]) {
      const normalized = query(command);
      expect(normalized).toStartWith("GIT_NO_LAZY_FETCH=1 ");
      expect(normalized).toContain(
        "'--no-pager' '--no-optional-locks' '-c' 'core.fsmonitor=false'",
      );
      if (!command.includes("status"))
        expect(normalized).toContain("'--no-textconv'");
    }
    expect(
      query(
        "git -c core.fsmonitor=false -C '/tmp/repo with spaces' diff -- src/file.ts",
      ),
    ).toContain("'-C' '/tmp/repo with spaces' 'diff'");
    expect(query("gh pr diff 12")).toStartWith(
      "PAGER=cat GH_PAGER=cat GLAB_PAGER=cat ",
    );
    expect(query("rg needle README.md")).toStartWith("'rg' '--no-config'");
  });

  test("explicit GET APIs and simple file queries stay available", () => {
    for (const command of [
      "gh api repos/owner/repo/pulls/12 --method GET --jq .number",
      "gh api --method=GET repos/owner/repo/issues/12/comments --paginate",
      "glab api projects/group%2Frepo/merge_requests/12 -X GET",
      "glab api --hostname gitlab.example.invalid projects/group%2Frepo/issues/12",
      "gh api --hostname github.example.invalid repos/owner/repo/issues/12",
      "glab mr view 12 --output json",
      "rg -n --fixed-strings 'config profile' opencode",
      "rg --files -g '*.ts'",
      "head -n 20 README.md",
      "tail -n 20 README.md",
      "cat README.md",
      "pwd",
    ])
      expect(() => query(command)).not.toThrow();
  });

  test("rejects shell composition and external program escapes", () => {
    for (const command of [
      "git status; touch /tmp/unsafe",
      "git status && git reset --hard",
      "git status | tee /tmp/unsafe",
      "git status > /tmp/unsafe",
      "git status\nrm /tmp/unsafe",
      "git show $(touch /tmp/unsafe)",
      "git show `touch /tmp/unsafe`",
      "git show <(touch /tmp/unsafe)",
      "git status &",
      "git status \\\n",
      "env git status",
      "/usr/bin/git status",
      "sh -c 'git status'",
      "python -c 'print(1)'",
      "sed -i '' README.md",
      "find . -exec rm '{}' '+'",
      "rg --pre sh query",
      "rg --hostname-bin touch query",
      "git -c alias.inspect='!touch /tmp/unsafe' inspect",
      "git -c core.fsmonitor=/tmp/unsafe status",
      "git --exec-path=/tmp log",
      "git diff --ext-diff",
      "git diff --textconv",
      "git log --show-signature",
      "git diff --output=/tmp/unsafe",
      "git show --output /tmp/unsafe",
      "git config user.name someone",
      "git remote add origin https://example.invalid/repo",
      "git remote set-url origin https://example.invalid/repo",
      "git remote remove origin",
      "git remote update",
      "git remote show origin",
      "git remote get-url --bad origin",
      "command gh issue close 12",
      "command -v /bin/sh",
      "command -v --help",
      "command -v gh glab",
      "git branch surprise",
      "git reset --hard",
      "ls *",
      "cat unmatched'",
      "git toString",
      "git constructor",
      "constructor",
      "__proto__",
    ])
      expect(() => query(command), command).toThrow("Read-only policy:");
  });

  test("rejects API mutation, implicit POST, method overrides and unknown endpoints", () => {
    for (const command of [
      "gh api repos/o/r/issues/1 -X DELETE",
      "gh api repos/o/r/issues/1 --method=PATCH",
      "gh api repos/o/r/issues/1 -X GET --method DELETE",
      "gh api repos/o/r/issues -f title=created",
      "gh api repos/o/r/issues -F title=created",
      "gh api repos/o/r/issues --input payload.json",
      "gh api repos/o/r/issues -H 'X-HTTP-Method-Override: DELETE'",
      "gh api repos/o/r/issues --header 'Authorization: unsafe'",
      "gh api repos/o/r/issues --header='X-HTTP-Method-Override: DELETE'",
      'gh api repos/o/r/issues --jq "$(touch forbidden)"',
      "git grep --open-files-in-pager=sh needle",
      "git grep --textconv needle",
      "git branch renamed",
      "git rev-list --output=file HEAD",
      "gh api graphql --method GET",
      "gh api user --method GET",
      "gh api https://example.org/execute --method GET",
      "gh api repos/o/r/../hooks --method GET",
      "gh api repos/o/r/issues --cache 1h",
      "glab api projects/1/issues -X POST",
      "glab api graphql",
      "gh pr merge 12",
      "gh issue close 12",
      "gh pr view 12 --web",
      "glab mr checkout 12",
      "glab issue update 12 --title changed",
      "glab ci view",
    ])
      expect(() => query(command), command).toThrow("Read-only policy:");
  });

  test("native and MCP write routes cannot masquerade as queries", () => {
    for (const tool of [
      "edit",
      "write",
      "apply_patch",
      "task",
      "delegate",
      "project_create_item",
      "project_update_item",
      "project_execute",
      "unknown_get_data",
      "project_read_then_delete",
      "context7_execute",
    ]) {
      expect(() => assertReadOnlyTool("reviewer", tool, {})).toThrow();
    }
    for (const tool of [
      "read",
      "glob",
      "grep",
      "skill",
      "webfetch",
      "context7_query-docs",
      "exa_get_code_context_exa",
      "gh_grep_searchGitHub",
    ]) {
      expect(() => assertReadOnlyTool("build", tool, {})).not.toThrow();
    }
    expect(() =>
      assertReadOnlyTool("build", "webfetch", { method: "DELETE" }),
    ).toThrow();
    expect(() =>
      assertReadOnlyTool("build", "webfetch", {
        headers: { "X-HTTP-Method-Override": "DELETE" },
      }),
    ).toThrow();
    expect(() =>
      assertReadOnlyTool("build", "context7_query-docs", { body: "mutation" }),
    ).toThrow();
  });

  test("unknown agents fail closed while known writers retain their tool capability", () => {
    expect(() => assertReadOnlyTool("general", "read", {})).toThrow();
    for (const role of ["coder", "scribe"]) {
      expect(() =>
        assertReadOnlyTool(role, "write", { content: "fixture" }),
      ).not.toThrow();
    }
  });

  // memory and a bash call with no command string were asserted here and
  // neither reaches this function: regular.ts answers memory before it, and the
  // native bash tool does not produce args without a command. An assertion
  // about an unreachable branch reads as a contract, which is worse than none.
  test("bash reaches one guard, and only the roles the table grants it", () => {
    expect(() => guardBash("scribe", { command: "ls" })).toThrow(
      "scribe cannot execute bash",
    );
    expect(() => guardBash("general", { command: "ls" })).toThrow();

    // A writer's command is bounded rather than normalized; a read-only role's
    // is normalized in place, which is the object the host goes on to execute.
    const writer: Record<string, unknown> = { command: "npm test > out.log" };
    expect(() => guardBash("coder", writer)).not.toThrow();
    expect(writer.command).toBe("npm test > out.log");
    expect(() =>
      guardBash("coder", { command: "npm run dev > dev.log 2>&1" }),
    ).toThrow("Unbounded log redirect");

    const reader: Record<string, unknown> = { command: "git status" };
    guardBash("build", reader);
    expect(String(reader.command)).toContain("core.fsmonitor=false");
  });

  test("accepted queries do not execute configured Git or ripgrep helper programs", () => {
    const directory = mkdtempSync(join(tmpdir(), "opencode-query-fixture-"));
    const tripwire = join(directory, "tripwire.sh");
    const marker = join(directory, "unexpected-write");
    const rgConfig = join(directory, "ripgrep.conf");
    const env = {
      PATH: process.env.PATH,
      HOME: directory,
      GIT_CONFIG_NOSYSTEM: "1",
      GIT_CONFIG_GLOBAL: "/dev/null",
      GIT_EXTERNAL_DIFF: tripwire,
      RIPGREP_CONFIG_PATH: rgConfig,
      TRIPWIRE_OUTPUT: marker,
    };
    function run(argv: string[]): string {
      const result = Bun.spawnSync(argv, { cwd: directory, env });
      expect(result.exitCode, result.stderr.toString()).toBe(0);
      return result.stdout.toString();
    }
    try {
      writeFileSync(
        tripwire,
        '#!/bin/sh\nprintf touched > "$TRIPWIRE_OUTPUT"\n',
        { mode: 0o755 },
      );
      writeFileSync(rgConfig, `--pre=${tripwire}\n`);
      run(["git", "init", "--quiet", "--template="]);
      writeFileSync(join(directory, ".gitattributes"), "*.txt diff=unsafe\n");
      writeFileSync(join(directory, "tracked.txt"), "before\n");
      run(["git", "add", ".gitattributes", "tracked.txt"]);
      run([
        "git",
        "-c",
        "user.name=Fixture",
        "-c",
        "user.email=fixture@example.invalid",
        "commit",
        "--quiet",
        "-m",
        "fixture",
      ]);
      run([
        "git",
        "remote",
        "add",
        "origin",
        "https://example.invalid/owner/repo.git",
      ]);
      run(["git", "config", "core.fsmonitor", tripwire]);
      run(["git", "config", "core.pager", tripwire]);
      run(["git", "config", "diff.external", tripwire]);
      run(["git", "config", "diff.unsafe.textconv", tripwire]);
      writeFileSync(join(directory, "tracked.txt"), "after\n");
      for (const command of [
        "git status --short",
        "git remote",
        "git remote -v",
        "git remote get-url origin",
        "git remote get-url --push --all origin",
        "git diff",
        "git log -p -n1",
        "git show HEAD",
        "git show --find-renames HEAD",
        "git log -30 --oneline",
        "git rev-list --left-right --count HEAD...HEAD",
        "git rev-list --parents -n 1 HEAD",
        "git branch --show-current",
        "git grep -n before HEAD -- tracked.txt",
        "git blame tracked.txt",
        "rg after tracked.txt",
      ]) {
        const output = run(["sh", "-c", query(query(command))]);
        expect(output).not.toBe("");
        expect(existsSync(marker), command).toBe(false);
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
});
