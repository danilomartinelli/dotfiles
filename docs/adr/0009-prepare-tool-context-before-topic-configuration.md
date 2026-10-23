---
status: accepted
---

# Prepare tool context before dependent topic configuration

Shell startup owns runtime preparation order. After sorted topic paths, it
loads the discovered `mise/mise.zsh` once before other topic configuration.
The classifier continues to classify files without choosing prerequisites.
This is one explicit prerequisite, not a general dependency scheduler.

Android previously queried Java before Mise activation because its topic sorted
first. A legacy configuration selector could therefore choose Java under a
context that activation subsequently removed. Consumers now query only after
successful preparation; failure preserves the previous environment. Mise policy
remains in `_scripts/mise-policy`, preserving normal project discovery and
personal overrides as required by
[ADR-0006](0006-own-mise-policy-without-changing-project-behavior.md).

Startup also restores the checkout's `bin` to the front of `PATH` after topic
configuration and activation. Topics declare their own directories without
knowing this global precedence rule. Mise's prompt and directory-change hooks
can prepend runtime paths again, including before the first prompt. Startup
registers its own `precmd` and `chpwd` hooks after them to restore managed-command
precedence while preserving project runtime selection. Repeated startup moves
these hooks to the end without duplicating them.

Tests cross real startup and topic files with the shared fake Mise in an isolated
home. They cover configuration context, preparation failure, colliding commands,
prompt and directory-change refreshes, and reload. The opt-in real-Mise
characterization also checks collisions across prompts, project runtime switches,
and reload. All run in temporary homes without applying the environment to the
owner's Mac.
