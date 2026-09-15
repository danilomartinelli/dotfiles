# Scribe keeps bash denied

`scribe` is a writer role whose `bash` permission is `deny`. That stays, and
`guardBash` reads the same answer the permission table renders, so the two can
no longer disagree.

## Considered options

An architecture review found that `regular.ts` gated the unbounded-redirect
check on `writerRoles`, which is `coder` and `scribe`, while `prompts.ts` denied
`scribe` bash — so half the gate could never be reached. Two readings of that
were available, and the same finding will be made again by whoever next reads
the two files together.

The tempting one is to grant `scribe` bash, which makes the existing gate true
and costs one character. It is backwards: a gate is evidence about what the
permission table says, not a reason to change it. Scribe writes documentation
from what a delegation already produced; giving it a shell to make an unrelated
guard tidy widens the only writer role that has no reason to run commands.

The other is to narrow the gate to `coder`, which is accurate but restates in
`permissions.ts` a decision `prompts.ts` owns — two places holding one fact, the
condition that produced the dead branch in the first place.

## Consequences

`roleMayRunBash` is the single answer. `prompts.ts` renders the permission table
from it and `guardBash` refuses from it, so a role the table denies cannot reach
the runtime guard and a gate cannot name a role that never arrives.

Adding a writer role that does need a shell is one edit in `roleMayRunBash`.
Adding one that does not needs no edit at all.

A future architecture review will still notice that `writerRoles` has two
members and that only one of them reaches `assertBoundedRedirect`. This file is
the answer to why, so that the review proposes neither of the two changes above
a second time.
