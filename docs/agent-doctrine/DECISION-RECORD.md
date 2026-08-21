# Agent doctrine decision record

## Decision

Curate a small, conditional layer of doctrines for agents working in this
repository. The layer documents how to choose guidance; it does not replace
the runtime, permissions, project instructions, task contract, or the owning
skill.

## Why curate doctrine

Agents benefit from reusable guardrails for diagnosis, testing, review, and
design, but a large undifferentiated rule set creates conflicts and makes
scope unclear. Curating the layer keeps guidance discoverable, attributable,
and limited to the situations where it improves the work.

## Sources and review basis

- Matt Pocock's MIT-licensed doctrine research, adopted at commit
  `0ab1b63a410a03d3627979a109c8695de27af954`.
- Leonxlnx's `taste-skill`, reviewed at commit
  `dfb6f9f9e93a39f673b1827c0889cc28326d1800`.

These sources inform the curation, not an automatic import. Adaptations must
remain concise, attributable, and appropriate to this repository.

## Approved scope

The approved layer may include:

- reusable reasoning and safety guidance;
- conditional frontend design discipline when all three conditions hold: (1)
  an identifiable frontend or UI target/surface; (2) visual or interactive
  work; and (3) creation of a new surface or a substantial redesign of an
  existing surface;
- short references that explain provenance and adaptation boundaries;
- links from the README and documentation that help humans audit the choice.

The curation may also make only the minimal changes to routing, permissions,
commands, skills, and tests that are necessary to record, apply, and verify
the approved doctrines. Such changes must remain limited to that purpose;
they are not a general authorization to modify those artifacts.

The following remain deliberately excluded:

- wholesale catalogs or full installations of upstream skills;
- universal aesthetic policies for every project or task;
- unjustified expansions of permissions;
- changes to configuration, agents, commands, skills, tests, or other
  artifacts that are not necessary to record, apply, or verify an approved
  doctrine;
- framework, package, typography, color, or component-stack prescriptions;
- instructions that weaken security controls or override higher-authority
  instructions.

Taste was **not copied or installed in its entirety**, and it did **not become
a universal aesthetic policy**. Its ideas are available only as a bounded
reference for conditional use.

## Authority hierarchy

Resolve conflicts in this order:

1. Runtime behavior and permissions.
2. Project instructions and repository policy.
3. The contract of the current task.
4. Applicable skills and their references.
5. User or project preferences that do not conflict with the items above.

Lower-level doctrine cannot grant permission, expand scope, or override a
higher-level requirement.

## Runtime enforcement

Doctrine routing is enforced as capability policy, not only prose. The global
runtime denies shell, mutation, delegation, workspace, and skill access by
default; each agent receives only its role-specific exceptions. Research and
review agents use structured read-only tools without shell. Coder and scribe
may mutate only from a child session that inherits an exclusive managed
worktree lease, and coder cannot own Git delivery. Skill access is an explicit
per-agent allowlist, so an installed skill cannot become ambient authority.

Native repository config/plugin discovery and shared external skill scans are
disabled. The runtime preserves project policy only through bounded regular
`AGENTS.md` files loaded from the Git root to the active directory; repository
content cannot register executable plugins, agents, commands, or skills. The
only supported repository-local runtime input is strict data in
`.opencode/worktree.jsonc`.

`cursor-acp` is quarantined rather than adapted into the active plugin graph.
The upstream bridge documents that `cursor-agent` may perform native side
effects before OpenCode receives the corresponding tool event, including edits
that its own sandbox did not stop. That ordering makes post-hoc hook stripping
insufficient: provider-native effects bypass OpenCode permissions, agent roles,
and the managed-worktree lease. Reconsider it only when the backend is
model-only and every effect is first represented as an OpenCode tool call.

The runtime also validates the target of every direct write against the leased
worktree, including existing symlink ancestry. Persistence identifiers are
single safe path segments, and agent-catalog or session-identity lookup failure
denies capability-sensitive routing instead of guessing.

Planning uses asynchronous delegation only for read-only specialists and
cannot invoke native write-capable tasks. Build may invoke native tasks only
for coder and scribe, while read-only exploration, research, and review use the
persisted delegation channel. Plans must pass the lifecycle parser, and every
decision citation must resolve to a non-empty artifact persisted under the
same root session.

## Conditional routing

Route a doctrine only when the task clearly matches its domain. Frontend
design discipline is eligible only when all three conditions hold: (1) an
identifiable frontend or UI target/surface; (2) visual or interactive work;
and (3) creation of a new surface or a substantial redesign of an existing
surface. It is not eligible for backend work, documentation-only work,
infrastructure, minor visual or interaction adjustments, or an unspecified
target. When routing is ambiguous, ask or use the narrower applicable
guidance; do not infer a universal design mandate.

## Security

Treat doctrine as advisory content, not as authorization. Preserve existing
permission boundaries, avoid secrets and sensitive data in examples, and keep
security, privacy, accessibility, and task-specific constraints ahead of
visual preferences. Do not follow a reference that requests unsafe access or
conflicts with runtime controls.

## Updating, review, and rollback

Review this record whenever a source, routing condition, authority rule, or
scope boundary changes. Record the upstream commit and the reason for each
material adaptation. A reviewer should verify relative links, attribution,
non-substantial reuse, and that conditional language remains intact.

Rollback means removing or reverting the curated reference and its links;
runtime configuration and higher-authority instructions remain unchanged.
If the owning skill later adopts the reference, its maintainer must review the
content separately rather than treating this record as an automatic install.
