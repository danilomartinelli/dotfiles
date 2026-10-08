---
status: accepted
---

# Expand catalog placeholders as literal values under one recognition rule

Catalog validation recognizes complete names, but expansion replaces substrings
and processes replacement values again for later names. A workspace path
containing literal `$HOME` can therefore change when the Dock consumer expands
`$WORKSPACE`, and names that share a prefix depend on their declaration order.

The shared Catalog module recognizes complete names identically for
validation and expansion, and expands only placeholders in the original text.
Replacement values remain literal, so substitution does not depend on the order
of distinct declarations. Dock, macOS preferences, and the checklist keep
ownership of their allowed names and supplied values. Whole-catalog validation
before effects and run-once gates remains required by
[ADR-0005](0005-validate-catalogs-before-any-effect.md).

Names follow the case-sensitive ASCII grammar `[A-Za-z_][A-Za-z0-9_]*`, so
recognition is independent of the machine's locale. Only `$NAME` is special:
each dollar is examined independently, with no escape, brace, or shell-expression
syntax. Validation rejects undeclared names; expansion preserves those tokens
whole. The existing helper functions and name/value argument pairs remain the
interface, with consumer wrappers retaining their declarations.

Both helpers validate the complete call before scanning the input. Missing
input, incomplete name/value pairs, invalid names, and duplicate names are
declaration errors, including duplicates with equal values. They return `1`,
report the error on stderr, and leave stdout empty. Empty input, empty
replacement values, and an input with no declarations remain valid.

This deliberately replaces sequential expansion and the prohibition on names
that share a prefix. No current tracked catalog explicitly needs sequential
expansion; retaining it would make ordinary directory values carry catalog
syntax and leave callers responsible for substitution order.
