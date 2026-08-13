# ADR 0001: QueueAdapter is an effect

Status: accepted — 2026-08-12.

## Context

Anga must support changing backends without requiring controllers, mailers, or
domain code to import concrete implementations. Kaikai makes effects visible
in every function signature.

## Decision

The public contract will be the `QueueAdapter` effect with the minimum
`enqueue` and `enqueue_at` operations. The backend is installed lexically at
the composition root; there will be no global adapter registry.

## Alternatives

- Pass a record of functions: explicit, but duplicates plumbing and closures
  are not serializable.
- Global configuration by name: familiar in Rails, but hides the effect, makes
  parallel tests harder, and is not idiomatic Kaikai.
- Protocols: current protocols are pure and cannot express an effect row that
  depends on the implementation.

## Consequences

Signatures show when an operation enqueues work, and tests can install
deterministic handlers. I/O adapters expose their own effects when installing
the handler.
