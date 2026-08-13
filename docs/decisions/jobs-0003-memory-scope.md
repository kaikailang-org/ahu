# ADR 0003: Memory is an ephemeral state machine

Status: accepted — 2026-08-12.

## Context

The first adapter must be simple, reproducible, and useful in tests. Starting
with a concurrent scheduler would mix the contract with supervision, shutdown,
locking, and persistence decisions.

## Decision

The in-memory adapter uses an immutable `State` and a lexical stateful handler.
The application or test decides when to call `pop_ready`, `perform_next`, or
`drain_ready`.

## Alternatives

- `Ref[State]`: supports shared identity, but introduces `Mutable` and races
  when shared across fibers.
- Internal actor: suitable for a later asynchronous adapter, but adds lifecycle
  and coordination before the contract is stable.
- Execute inline while enqueueing: does not test scheduling or represent a
  queue.

## Consequences

The implementation is deterministic and easy to test. It does not survive
restarts, run by itself, or provide concurrency guarantees; these limitations
are an explicit part of its API and documentation.
