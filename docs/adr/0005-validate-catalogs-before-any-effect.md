---
status: accepted
---

# Validate catalogs whole before any effect and expand placeholders literally

A catalog row that is wrong on its text alone is a repository error, so every
consumer runs its catalog's rules over the whole file before its first effect
and before any run-once gate, which would otherwise hide a broken row until a
reset. A broken catalog therefore stops the run at its consumer, and CI runs the
same rules over every tracked catalog without running a consumer.

The rules are a shell validator kept beside each consumer rather than a schema
declared in the catalog header. Some catalogs constrain one column by another,
and expressing that declaratively would mean maintaining a condition language
in POSIX sh.

A fact about the machine, such as a missing app or an identifier Launch
Services does not know, is not a rule and stays a warning at apply time.

## Placeholders

A catalog value may name a path through a `$NAME` placeholder. Validation and
expansion recognize the same complete name, the case-sensitive ASCII grammar
`[A-Za-z_][A-Za-z0-9_]*`, independently of the machine's locale, and only
placeholders in the original text expand. Replacement values stay literal: a
workspace path that itself contains `$HOME` does not change when `$WORKSPACE`
expands, and names that share a prefix do not depend on declaration order.

Only `$NAME` is special, with no escape, brace or shell-expression syntax.
Validation rejects undeclared names; expansion preserves them whole. Each
consumer keeps ownership of its allowed names and supplied values, and a
malformed declaration, such as a missing value, an invalid name or a duplicate,
is an error before any input is scanned.

Sequential expansion, where a replacement is processed again for later names,
was rejected: it makes ordinary directory values carry catalog syntax and
leaves callers responsible for substitution order.
