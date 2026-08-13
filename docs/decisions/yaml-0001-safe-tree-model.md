# 0001: Usar un árbol seguro con claves string

Estado: aceptada.

## Contexto

YAML puede representar mappings con claves arbitrarias, tags de aplicación y
grafos mediante anchors y aliases. Reo necesita documentos humanos simples y
predecibles, no construcción dinámica de objetos.

## Decisión

`YamlValue` será un árbol algebraico y los mappings tendrán claves `String`.
0.1 rechazará tags, anchors, aliases, merge keys y claves complejas.

## Consecuencias

El resultado es portable, comparable y seguro por defecto. Algunos documentos
YAML válidos no serán aceptados hasta que exista una representación explícita
y acotada para esas capacidades.
