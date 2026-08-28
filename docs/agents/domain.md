# Domain Docs

How the engineering skills should consume this repository's domain
documentation when exploring the codebase.

This repository is **single-context**: one `CONTEXT.md` at the root and one
`docs/adr/` directory. There is no `CONTEXT-MAP.md` and no per-context split.

## Before exploring, read these

- **`CONTEXT.md`** at the repository root.
- **`docs/adr/`**: read ADRs that touch the area you are about to work in.

If any of these files do not exist, **proceed silently**. Do not flag their
absence and do not suggest creating them upfront. The `/domain-modeling` skill
(reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates
them lazily when terms or decisions actually get resolved.

## File structure

```text
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-topic-installer-idempotence.md
│   └── 0002-mise-owns-language-package-clis.md
└── <topic>/
```

`docs/` is a reserved non-topic in `_scripts/topic-catalog`, so adding domain
documentation here never registers a topic or affects setup, Zsh startup, or
linking.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor
proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`.
Do not drift to synonyms the glossary explicitly avoids.

If the concept you need is not in the glossary yet, that is a signal: either
you are inventing language the project does not use (reconsider) or there is a
real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than
silently overriding:

> *Contradicts ADR-0002 (Mise owns language-package CLIs), but worth reopening
> because…*
