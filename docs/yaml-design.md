# Diseño de kai-yaml 0.1

`kai-yaml` es la frontera de serialización YAML para el ecosistema Kaikai. Su
primer consumidor será Reo, pero el paquete no contiene conceptos de idiomas,
traducciones o pluralización.

## Objetivos

- Interpretar el YAML cotidiano de archivos de configuración.
- Usar un modelo de valores pequeño, inmutable y explícito.
- Entregar errores recuperables con posición de origen.
- No ejecutar constructores, tags ni referencias definidos por el documento.
- Mantener el parser puro y hacer visible el IO al cargar archivos.
- Producir una serialización canónica útil para snapshots y herramientas.

No son objetivos de 0.1 editar documentos conservando comentarios, aceptar
streams multidocumento, implementar el grafo de anchors/aliases ni cubrir cada
producción de la especificación YAML.

## Capas

```text
String ── yaml.parser ──> Result[YamlValue, ParseError]
   ▲                              │
   │                              ├── yaml.value: consultas totales
File / lector inyectado           └── yaml.encoder: salida canónica
   │
yaml.loader
```

`yaml.parser` no declara efectos. `yaml.loader` es la única capa que conoce la
lectura externa y ofrece dos entradas:

- `load(path) / File` para aplicaciones;
- `load_with(path, read) / e` para filesystems alternativos y pruebas.

## Modelo de representación

El modelo refleja las tres primitivas de YAML —scalar, sequence y mapping— y
resuelve el subconjunto cotidiano del core schema de YAML 1.2: null,
booleanos, enteros decimales y reales finitos. `yes`, `no`, `on` y `off`
siguen siendo strings; esto evita la coerción sorprendente heredada de YAML
1.1. Las formas octales, hexadecimales, infinitos y NaN quedan como strings en
0.1.

Los mappings usan `[Pair[String, YamlValue]]` en vez de `Map`. Así preservan el
orden fuente y pueden detectar claves duplicadas antes de perder información.
Solo se aceptan claves string porque es la forma interoperable requerida por
configuración, manifests y catálogos de traducción.

## Parser

El parser trabaja en dos niveles:

1. normaliza saltos de línea y convierte cada línea en `(número, indentación,
   texto)`;
2. un descenso recursivo interpreta collections block, y un cursor separado
   interpreta valores flow y strings quoted.

Los comentarios se eliminan únicamente fuera de strings. La búsqueda de `:`
para mappings también respeta comillas y profundidad flow, por lo que valores
como URLs no se confunden con pares.

Se soportan scalars literales y folded con `-`, clip por defecto y `+`. La
salida folded implementa el caso de configuración habitual; los scalars flow
multilínea y los indicadores explícitos de indentación se rechazan.

## Seguridad

Tags, anchors, aliases y merge keys cambian el modelo desde un árbol hacia un
grafo y pueden activar construcción específica de la aplicación en otros
ecosistemas. 0.1 los reconoce en sus posiciones de inicio y retorna
`UnsupportedFeature`; nunca los trata silenciosamente como texto.

Las claves duplicadas retornan `DuplicateKey`. Adoptar "first wins" o "last
wins" haría que una traducción o configuración efectiva dependiera de una
convención invisible y distinta entre parsers.

## Encoder

El encoder siempre usa block collections y double quotes para strings y
claves. Eso sacrifica estilo, pero garantiza que un valor como `true`, `null`
o `0123` no cambie de tipo al volver a parsearse. El orden de entrada se
mantiene y la salida siempre termina con newline.

## Integración con Reo

Reo dependerá de `kai-yaml` y transformará `YamlValue` en su propio catálogo.
La validación específica queda aguas arriba:

```text
config/locales/es.yml
        │ File
        ▼
   yaml.load
        │ YamlValue
        ▼
   reo.catalog.from_yaml
        │ CatalogError con path semántico
        ▼
      Voice
```

Así, un YAML sintácticamente válido puede fallar como catálogo con un error de
Reo preciso —por ejemplo, una traducción que sea una lista— sin convertir esa
restricción del dominio en una regla global del parser.

## Evolución

1. 0.1: subset seguro para configuración, loader y encoder canónico.
2. 0.2: streams mediante una API separada y scalars multilínea completos.
3. Futuro: anchors/aliases como grafo explícito, solo si existe un caso de uso
   que justifique límites de expansión, detección de ciclos y una API segura.
