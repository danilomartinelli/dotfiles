# Delegation notice delivery

Accepted design from the Candidate 02 interview, confirmed by the repository
owner and implemented in `Delegations`. The owning
[runtime guide](../../opencode/orchestrator/README.md) documents delivery behavior
and its limits.

Canonical implementation specification:
[issue #46](https://github.com/danilomartinelli/dotfiles/issues/46).

`Delegations` owns both delivery operations, keeping the persisted protocol
behind its interface while native presentation and transport stay in `regular.ts`.
The adapter requests a wake or inclusion in the root's current message without
coordinating reservation and restoration itself.

## Interface and ownership

The existing `Delegations` module exposes two operations:

```ts
type RootNotice = Readonly<
  Pick<Delegation, "id" | "role" | "status" | "route">
>;

declare class Delegations {
  wakeRoot(
    root: string,
    send: (notices: readonly RootNotice[]) => Promise<boolean>,
  ): Promise<void>;

  includeInRootMessage(
    root: string,
    append: (notices: readonly RootNotice[]) => void,
  ): Promise<void>;
}
```

`Delegations` owns selection, grouping, atomic reservation, consumption, and
conditional restoration. Reservation identities and flags remain private;
`notifications`, `restoreNotifications`, and `reconciledNotifications` are no
longer public operations. The adapter receives presentation data, not reservation
tokens.

The adapter in `regular.ts` owns native message formatting, role and route
resolution, model selection, the session directory, and OpenCode transport.
Those steps stay inside the `send` callback so a failure after reservation can
restore the notices. Shared notice text is formatted there for both destinations.

## Ordering and failures

`wakeRoot` consumes recorded state without running delegation recovery: it can
be called by a stop callback during recovery itself. It reserves before invoking
the adapter, preserves the existing grouping policy, and does not call the
adapter for an empty batch. A rejected send (`false`) or an exception from the
adapter restores only notices still belonging to the same delegation, attempt,
and state. Adapter failures remain absorbed; journal failures remain observable.

`includeInRootMessage` runs delegation recovery before reserving the pending
notices, without waiting for other children to settle. Recovery may itself
trigger a wake and consume notices before this collection. The append callback
is synchronous and is skipped for an empty batch. Recovery and append errors
propagate; an append failure does not gain restoration that the current path
does not provide.

## Preserved guarantees

- Successful results remain grouped until all children settle for spontaneous
  wakes. Failures, timeouts, and pending stops can wake the root while siblings
  remain active. Preserve the existing selection of every other terminal state.
- A pending stop and its later terminal state retain their separate notices.
  A delayed delivery failure cannot rearm a resumed attempt or a changed state.
- The two destinations share the existing journal and atomic reservation.
  Consuming a notice through one makes it unavailable to the other unless the
  existing restoration rule applies.
- Delivery targets the existing root session. It neither creates sessions nor
  releases delegation ownership or changes delegation status.
- A successful send means the transport returned without an error, not that the
  root inspected the delegated result. An inline delivery means the adapter
  appended to the current message, not that native persistence was confirmed.
- Failed sends become available at a later existing collection opportunity.
  There is no new retry scheduler, outbox, lease, acknowledgement, or recovery
  of a process crash between reservation and delivery.
- Keep the journal format and existing records compatible. No migration or
  change to delegation recovery or resume is part of this refactor.

## Alternatives considered

A separate `NotificationDelivery` module would require an internal interface
for journal recovery, reservation, and restoration. Configuring handlers once
in `SessionJournals` would shorten hooks but require additional binding and an
opaque message target. Two operations on the existing owner offer the best
locality with the least extra coordination for the two actual callers. This
reversible placement decision does not need an ADR.

## Integration and validation

Use the existing SQLite fixtures and exercise the delivery interface with a
controllable external adapter. Observe delivered batches and later collection
opportunities rather than exposing reservation tokens for tests.

- Cover grouping, urgent failures, pending stops followed by terminal notices,
  empty batches, and consumption shared across both destinations and journal
  instances.
- Cover returned rejection and thrown errors, including an in-flight send that
  fails after the delegation has resumed or changed state.
- Preserve recovery through a root message and a stop callback that delivers
  without recursively recovering. Keep the inline append failure behavior.
- Retain native hook coverage for text, route, directory, and message metadata.
  Replace tests of the old public reservation protocol once equivalent behavior
  is covered through the new interface.
- Run the focused orchestration tests, type checks, applicable static checks,
  and the required safe suite. Keep the owning runtime guide aligned with the
  implementation; documentation validation alone does not prove delivery.
