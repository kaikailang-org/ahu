# 0001: Use a safe tree with string keys

Status: accepted.

## Context

YAML can represent mappings with arbitrary keys, application tags, and graphs
through anchors and aliases. Reo needs simple, predictable documents for
humans, not dynamic object construction.

## Decision

`YamlValue` will be an algebraic tree, and mappings will have `String` keys.
Version 0.1 will reject tags, anchors, aliases, merge keys, and complex keys.

## Consequences

The result is portable, comparable, and safe by default. Some valid YAML
documents will not be accepted until there is an explicit, bounded
representation for those capabilities.
