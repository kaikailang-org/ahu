# kai-yaml 0.1 design

`kai-yaml` is the YAML serialization boundary for the Kaikai ecosystem. Reo is
its first consumer, but the package contains no language, translation, or
pluralization concepts.

## Goals

- Interpret the everyday YAML found in configuration files.
- Use a small, immutable, explicit value model.
- Return recoverable errors with source positions.
- Never execute constructors, tags, or references defined by a document.
- Keep the parser pure and make file-loading I/O visible.
- Produce canonical serialization suitable for snapshots and tools.

Preserving comments while editing, accepting multi-document streams,
implementing the anchor/alias graph, and covering every YAML grammar production
are not goals for 0.1.

## Layers

```text
String ── yaml.parser ──> Result[YamlValue, ParseError]
   ▲                              │
   │                              ├── yaml.value: total queries
File / injected reader            └── yaml.encoder: canonical output
   │
yaml.loader
```

`yaml.parser` declares no effects. `yaml.loader` is the only layer that knows
about external reads and provides two entry points:

- `load(path) / File` for applications;
- `load_with(path, read) / e` for alternate filesystems and tests.

## Representation model

The model reflects YAML's three primitives—scalar, sequence, and mapping—and
resolves the everyday subset of the YAML 1.2 core schema: null, booleans,
decimal integers, and finite real numbers. `yes`, `no`, `on`, and `off` remain
strings, preventing the surprising coercion inherited from YAML 1.1. Octal and
hexadecimal forms, infinities, and NaN remain strings in 0.1.

Mappings use `[Pair[String, YamlValue]]` rather than `Map`. This preserves
source order and allows duplicate keys to be detected before information is
lost. Only string keys are accepted because that is the interoperable form
required by configuration, manifests, and translation catalogs.

## Parser

The parser operates at two levels:

1. it normalizes line endings and converts each line to `(number, indentation,
   text)`;
2. recursive descent interprets block collections, while a separate cursor
   interprets flow values and quoted strings.

Comments are removed only outside strings. Searching for `:` in mappings also
respects quotes and flow depth, so values such as URLs are not mistaken for
pairs.

Literal and folded scalars support `-`, default clipping, and `+`. Folded output
implements the common configuration case; multiline flow scalars and explicit
indentation indicators are rejected.

## Security

Tags, anchors, aliases, and merge keys change the model from a tree to a graph
and can trigger application-specific construction in other ecosystems. Version
0.1 recognizes them at their starting positions and returns
`UnsupportedFeature`; it never silently treats them as text.

Duplicate keys return `DuplicateKey`. Adopting “first wins” or “last wins”
would make the effective translation or configuration depend on an invisible
convention that differs among parsers.

## Encoder

The encoder always uses block collections and double quotes for strings and
keys. This sacrifices style, but guarantees that values such as `true`, `null`,
or `0123` do not change type when parsed again. Input order is preserved, and
output always ends with a newline.

## Reo integration

Reo depends on `kai-yaml` and transforms `YamlValue` into its own catalog.
Domain-specific validation remains upstream:

```text
config/locales/es.yml
        │ File
        ▼
   yaml.load
        │ YamlValue
        ▼
   reo.catalog.from_yaml
        │ CatalogError with semantic path
        ▼
      Voice
```

This allows syntactically valid YAML to fail as a catalog with a precise Reo
error—for example, when a translation is a list—without turning that domain
restriction into a global parser rule.

## Evolution

1. 0.1: safe configuration subset, loader, and canonical encoder.
2. 0.2: streams through a separate API and complete multiline scalars.
3. Future: anchors and aliases as an explicit graph, only when a use case
   justifies expansion limits, cycle detection, and a safe API.
