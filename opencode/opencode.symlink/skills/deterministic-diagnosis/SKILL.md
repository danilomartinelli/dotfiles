---
name: deterministic-diagnosis
description: "Reproduce failures with a deterministic red command before changing code"
---

# Deterministic diagnosis

Use this when a defect is reported or suspected.

1. State the observed behavior and the expected behavior.
2. Write one narrow **red command**: a repeatable test, check, or minimal
   reproduction that fails for the stated reason.
3. Record the command, inputs, environment assumptions, and failure output.
4. Change one causal thing at a time; rerun the same command.
5. Stop when the command is green, then run the smallest relevant regression
   checks.

Do not call a diagnosis complete because a plausible explanation exists. If a
red command cannot be made deterministic, report the missing evidence and the
next observation needed.

## Attribution

Local adaptation informed by Matt's MIT-licensed doctrine research at commit
`0ab1b63a410a03d3627979a109c8695de27af954`; this file is not a wholesale copy.
