---
name: public-seam-tdd
description: "Drive changes through public-seam behavior tests before implementation details"
---

# Public-seam TDD

Prefer a test at the narrowest stable public seam: command, API, exported
function, user-visible workflow, or documented interface. Start with the
smallest failing example, implement only enough behavior to pass it, then
refactor without changing the contract.

Avoid tests coupled only to private helpers, incidental structure, snapshots
that hide behavior, or mocks that replace the seam under test. Add lower-level
tests when they protect a meaningful invariant that the public seam cannot
observe.

## Attribution

Local adaptation informed by Matt's MIT-licensed doctrine research at commit
`0ab1b63a410a03d3627979a109c8695de27af954`; this file is not a wholesale copy.
