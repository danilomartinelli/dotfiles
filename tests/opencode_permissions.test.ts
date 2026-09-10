import { describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { rolePermissions } from "../opencode/orchestrator/prompts";
import {
  assertReadOnlyTool,
  readOnlyRoles,
} from "../opencode/orchestrator/permissions";

function query(command: string, role = "reviewer"): string {
  const args = { command };
  assertReadOnlyTool(role, "bash", args);
  return args.command;
}

describe("regular read-only tool boundary", () => {
  test("CLI discovery reports availability without executing the CLI", () => {
    const directory = mkdtempSync(join(tmpdir(), "opencode-cli-discovery-"));
    const marker = join(directory, "executed");
    try {
      for (const cli of ["gh", "glab"]) {
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
      "command -v sh",
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
      "memory",
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
    expect(() => assertReadOnlyTool("build", "bash", {})).toThrow();
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
        "git blame tracked.txt",
        "rg after tracked.txt",
      ]) {
        const output = run(["sh", "-c", query(command)]);
        expect(output).not.toBe("");
        expect(existsSync(marker), command).toBe(false);
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
});
