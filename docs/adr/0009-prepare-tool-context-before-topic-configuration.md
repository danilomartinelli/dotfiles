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
knowing this global precedence rule. Repeated startup remains idempotent.
This governs the completed startup pass; it does not replace Mise's hooks for
subsequent project changes.

Tests cross real startup and topic files with the shared fake Mise in an isolated
home. They cover configuration context, preparation failure, colliding commands
and reload. They do not characterize an installed Mise or apply the environment
to the owner's Mac.
