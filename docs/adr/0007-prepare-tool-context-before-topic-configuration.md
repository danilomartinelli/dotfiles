---
status: accepted
---

# Prepare tool context before dependent topic configuration

Shell startup owns runtime preparation order. After sorted topic paths, it
loads the discovered `mise/mise.zsh` once before other topic configuration.
The classifier continues to classify files without choosing prerequisites.
This is one explicit prerequisite, not a general dependency scheduler.

A topic that sorts before Mise, such as Android, would otherwise query Java
under a context that activation then replaces. Consumers query only after
successful preparation, and a failed preparation preserves the previous
environment. Mise policy stays in `_scripts/mise-policy`, preserving normal
project discovery and personal overrides as required by
[ADR-0006](0006-own-mise-policy-without-changing-project-behavior.md).

Startup also restores the checkout's `bin` to the front of `PATH` after topic
configuration and activation. Topics declare their own directories without
knowing this global precedence rule. Mise's prompt and directory-change hooks
can prepend runtime paths again, including before the first prompt, so startup
registers its own `precmd` and `chpwd` hooks after them to restore
managed-command precedence while preserving project runtime selection. Repeated
startup moves these hooks to the end without duplicating them.
