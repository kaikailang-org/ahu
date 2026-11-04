# ahu.yaml

`ahu.yaml` is a safe YAML 1.2 library for Kaikai. It converts human-readable
text into an explicit value tree without constructing arbitrary objects or
hiding I/O.

It targets application configuration and localization catalogs such
as those consumed by Reo. It includes:

- indentation-based mappings and sequences;
- flow mappings and sequences (`{...}` and `[...]`);
- plain, single-quoted, and double-quoted strings;
- YAML escapes in double-quoted strings, including Unicode;
- `null`, booleans, decimal integers, and finite real numbers from the YAML 1.2
  core schema;
- literal (`|`) and folded (`>`) block scalars with chomping;
- comments outside strings;
- recoverable errors with line and column positions;
- duplicate-key rejection;
- loading through the `File` effect or an injected reader function;
- deterministic serialization and total query helpers.

## Import

```kai
import ahu.yaml
import ahu.yaml.value
```

## Parsing

```kai
let source = "es:\n  greeting: Hola\n  enabled: true\n"

match yaml.parse(source) {
  Err(problem) -> panic("invalid YAML: #{problem.line}:#{problem.column}")
  Ok(document) -> {
    let greeting = value.get_path(document, ["es", "greeting"])
    assert greeting == Some(YString("Hola"))
  }
}
```

The model does not use `JsonValue` because YAML defines its own boundary and
must be free to evolve without distorting JSON:

```kai
type YamlValue
  = YNull
  | YBool(Bool)
  | YInt(Int)
  | YReal(Real)
  | YString(String)
  | YSequence([YamlValue])
  | YMapping([Pair[String, YamlValue]])
```

Mappings preserve document order. Keys are strings; complex YAML keys are not
part of the safe contract.

## Loading files

The normal operation declares I/O in its signature:

```kai
let catalog = yaml.load("config/locales/es.yml")
# Result[YamlValue, LoadError] / File
```

Tests, embedded assets, or virtual filesystems can inject the reader without
simulating global state:

```kai
import ahu.yaml.loader

let catalog = loader.load_with("es.yml", path =>
  if path == "es.yml" {
    Ok("es:\n  hello: Hola\n")
  } else {
    Err("not found")
  })
```

## A catalog for Reo

```yaml
es:
  welcome:
    title: "Hola, %{name}"
    inbox:
      one: "Tienes un mensaje"
      other: "Tienes %{count} mensajes"
```

`ahu.yaml` only interprets YAML. Reo is responsible for validating that the
root contains locales, that a leaf is a translation, and that `one`/`other`
form a valid plural. This boundary keeps the parser general and leaves Reo in
control of its domain.

## Serialization

`yaml.stringify` produces deterministic block YAML, always quotes strings and
keys, preserves mapping order, and ends with a newline. Its goal is a stable
representation for snapshots and tools; it does not preserve comments or the
original style.

## Deliberate limitations

Anchors, aliases, merge keys, tags, complex keys, multiple documents, and
multiline flow scalars are rejected with a `ParseError`. They are never ignored
or interpreted partially. Comments, whitespace, and style are not preserved
for round-trip editing.

The architecture and rationale for this scope are documented in
[`yaml-design.md`](yaml-design.md).

## Tests

`make tier1` runs the tests in `tests/unit/yaml_parser_test.kai` and
`tests/unit/yaml_value_encoder_test.kai`.
