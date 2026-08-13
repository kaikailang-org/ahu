# kai-yaml

`kai-yaml` es una librería segura de YAML 1.2 para Kaikai. Convierte texto
humano en un árbol de valores explícito, sin construir objetos arbitrarios ni
ocultar IO.

La versión 0.1 está pensada para configuración de aplicaciones y catálogos de
localización como los que consumirá Reo. Incluye:

- mappings y sequences por indentación;
- mappings y sequences flow (`{...}` y `[...]`);
- strings plain, single-quoted y double-quoted;
- escapes YAML en strings double-quoted, incluido Unicode;
- `null`, booleanos, enteros decimales y reales finitos del core schema YAML 1.2;
- scalars de bloque literales (`|`) y folded (`>`) con chomping;
- comentarios fuera de strings;
- errores recuperables con línea y columna;
- rechazo de claves duplicadas;
- carga mediante el efecto `File` o una función lectora inyectada;
- serialización determinista y helpers de consulta total.

## Dependencia

Durante el desarrollo local:

```toml
[dependencies]
yaml = { path = "../kai-yaml" }
```

El paquete se llama `kai-yaml`; la dependencia usa `yaml` como alias de módulo
idiomático:

```kai
import yaml
import yaml.value
```

## Parsear

```kai
let source = "es:\n  greeting: Hola\n  enabled: true\n"

match yaml.parse(source) {
  Err(problem) -> panic("YAML inválido: #{problem.line}:#{problem.column}")
  Ok(document) -> {
    let greeting = value.get_path(document, ["es", "greeting"])
    assert greeting == Some(YString("Hola"))
  }
}
```

El modelo no usa `JsonValue` porque YAML distingue una frontera propia y puede
evolucionar sin deformar JSON:

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

Los mappings conservan el orden del documento. Las claves son strings: las
claves complejas de YAML no forman parte del contrato seguro de 0.1.

## Cargar archivos

La operación normal declara IO en la firma:

```kai
let catalog = yaml.load("config/locales/es.yml")
# Result[YamlValue, LoadError] / File
```

Para pruebas, assets embebidos o un filesystem virtual puede inyectarse la
lectura sin simular estado global:

```kai
import yaml.loader

let catalog = loader.load_with("es.yml", path =>
  if path == "es.yml" {
    Ok("es:\n  hello: Hola\n")
  } else {
    Err("not found")
  })
```

## Un catálogo para Reo

```yaml
es:
  welcome:
    title: "Hola, %{name}"
    inbox:
      one: "Tienes un mensaje"
      other: "Tienes %{count} mensajes"
```

`kai-yaml` solamente interpreta YAML. Será responsabilidad de Reo validar que
la raíz contiene locales, que una hoja es una traducción y que `one`/`other`
forman un plural válido. Esta frontera mantiene al parser general y a Reo
dueño de su dominio.

## Serializar

`yaml.stringify` produce block YAML determinista, siempre entrecomilla strings
y claves, preserva el orden del mapping y termina con newline. El objetivo es
una representación estable para snapshots y herramientas; no conserva
comentarios ni el estilo original.

## Límites deliberados de 0.1

Anchors, aliases, merge keys, tags, claves complejas, múltiples documentos y
scalars flow multilínea se rechazan con un `ParseError`. No se ignoran ni se
interpretan parcialmente. Tampoco se preservan comentarios, whitespace o
estilo para edición round-trip.

La arquitectura y las razones de este alcance están en
[`docs/design.md`](docs/design.md).

## Desarrollo

```sh
./scripts/check.sh
```
