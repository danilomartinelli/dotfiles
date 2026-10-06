---
status: accepted
---

# Validate catalogs whole by consumer-owned rules before any effect

A catalog row that is wrong on its text alone is a repository error, so every
consumer runs its catalog's rules over the whole file before its first effect
and before any run-once gate, which would otherwise hide a broken row until a
reset. A broken catalog therefore stops the run at its consumer, and CI runs the
same rules over every tracked catalog without running a consumer.

The rules are a shell validator kept beside each consumer rather than a schema
declared in the catalog header. Two of the four catalogs constrain one column
by another, and expressing that declaratively would mean maintaining a
condition language in POSIX sh.

A fact about the machine, such as a missing app or an identifier Launch
Services does not know, is not a rule and stays a warning at apply time.
