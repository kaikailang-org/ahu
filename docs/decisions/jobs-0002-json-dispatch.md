# ADR 0002: Workers by name with JSON arguments

Status: accepted — 2026-08-12.

## Context

Active Job can serialize objects through serializers and GlobalID. Kaikai does
not have runtime module reflection, and a function or closure is not a portable
payload for a durable queue.

## Decision

A job contains a stable worker name and `[JsonValue]`. The application provides
an exhaustive dispatcher that maps the name to a typed function. `ahu.jobs.codec`
defines the canonical representation for future adapters.

## Alternatives

- Store closures: prevents persistence and deployments across versions.
- Use an unstructured `String` for arguments: pushes parsing and invariants
  into every worker.
- Import Tino: useful for complex boundary models, but unnecessary in the base
  contract; each application can validate them with Tino before enqueueing.

## Consequences

Serialization boundaries are evident. Renaming a worker is a compatibility
change that must include an alias in the dispatcher while old jobs exist.
