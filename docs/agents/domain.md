# Domain docs

This repository uses a single-context layout. Its macOS configuration topics
share one domain vocabulary and one set of architecture decision records.

## Before exploring

- Read `GLOSSARY.md` at the repository root when it exists.
- Read ADRs under `docs/adr/` that apply to the area being changed.

If these files do not exist, proceed silently. Do not flag their absence or
create empty placeholders. The `/domain-modeling` skill creates them when
terms or architectural decisions are resolved.

## File structure

```text
/
├── GLOSSARY.md
└── docs/
    └── adr/
        └── NNNN-decision-title.md
```

## Use the glossary's vocabulary

Use glossary terms in issue titles, proposals, hypotheses, tests, code, and
documentation. Avoid synonyms the glossary explicitly rejects. If a needed
concept is absent, reconsider whether it belongs to the domain; record a real
vocabulary gap for `/domain-modeling`.

## Flag ADR conflicts

When a proposal contradicts an existing ADR, identify the ADR and explain why
the decision should be revisited rather than silently overriding it.
