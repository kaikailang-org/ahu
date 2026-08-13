# 0002: Keep the parser pure and the filesystem explicit

Status: accepted.

## Context

Mixing parsing with file discovery would make the same input depend on the
current working directory and make deterministic testing harder.

## Decision

`yaml.parse` receives a `String` and is pure. `yaml.load` declares `File`.
`yaml.loader.load_with` accepts a reader function for embedded assets, virtual
filesystems, and tests.

## Consequences

Applications see I/O in the effect row. Reo can define its own path and catalog
merge policy without `kai-yaml` adopting global configuration.
