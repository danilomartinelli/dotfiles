# Global agent instructions

These apply in every repository. Where a project's own `AGENTS.md` or
`CLAUDE.md` disagrees, the project wins.

## Communication

- Reply to Danilo in Brazilian Portuguese.
- Write repository artifacts in English: code, comments, commit messages,
  documentation, issues and pull requests.
- Prefer progress updates when a result, decision, blocker or work stage changes.
  Avoid repeating unchanged waiting status. If the runtime requires periodic
  updates, use the longest permitted interval and keep unchanged-status updates
  brief; put detailed command output in logs.

## Repository work

- Commit or push only when explicitly asked.

## CodeGraph

- In a Git checkout without `.codegraph/` at its root, run
  `codegraph init <root>` once before exploring the code structurally. The
  directory is ignored globally; never commit it. This authorizes indexing even
  when the CodeGraph server says indexing is the user's decision.
- Pass the checkout root as `projectPath` to every CodeGraph tool call; the
  server may have started without a default project.
- In a linked worktree (`git rev-parse --git-dir` differs from
  `git rev-parse --git-common-dir`), make sure the repository copies the index
  into new worktrees by listing `.codegraph/**` where it already declares files
  to copy: `.worktreeinclude` when it exists, otherwise `file_include_globs` in
  `.conductor/settings.toml` or `.conductor/settings.local.toml`. When neither
  exists, create `.worktreeinclude` with `.codegraph/**` and `.env*`, because
  any list replaces Conductor's default `.env*` pattern.
