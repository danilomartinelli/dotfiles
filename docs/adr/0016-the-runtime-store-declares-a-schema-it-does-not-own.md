# The runtime store declares a schema it does not own

`opencode/_runtime-store.sh` names the tables and columns it reads out of
OpenCode's database and verifies them before its first query. OpenCode owns
that schema and may change it without telling this repository anything.

## Considered options

Not declaring it is what the module did before, and it is the normal answer for
a reader of someone else's database: write the query, and let it fail if the
shape changes.

It does not fail. The doctor's queries are counts and existence checks, so a
renamed column surfaces as an SQLite error on one path and as `0` on another,
and a dropped table surfaces as a condition that quietly stops finding
anything. A tool whose entire job is to notice accumulating state is the worst
possible place for a silent nothing-found, because nothing-found is also what
success looks like.

Deriving the dependency from the SQL instead of declaring it beside it was the
alternative to a second list. The statements are composed across several
functions and one of them is a retention predicate spliced together at open
time, so anything deriving the column set would have to parse SQL this module
builds — a harder problem than the one being solved.

## Consequences

The declaration is a second statement of a fact the queries already contain,
and the two can drift: a new query reading a column nobody declared will work
until the day it does not. `tests/opencode_runtime_store_test.sh` and
`tests/opencode_doctor_test.sh` each hold their own fixture schema against the
declaration, which catches a fixture that stopped covering the dependency but
not a query that outgrew it.

When OpenCode does change its schema, the failure names the table or column
that went away and points at this module. That is the whole return: the repair
is still a person's, but they are told what to repair instead of being told
that everything is fine.
