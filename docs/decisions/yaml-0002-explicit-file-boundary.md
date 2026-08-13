# 0002: Mantener el parser puro y el filesystem explícito

Estado: aceptada.

## Contexto

Mezclar parsing y búsqueda de archivos haría que la misma entrada dependiera
del cwd y dificultaría pruebas deterministas.

## Decisión

`yaml.parse` recibe `String` y es puro. `yaml.load` declara `File`.
`yaml.loader.load_with` recibe una función lectora para assets embebidos,
filesystems virtuales y pruebas.

## Consecuencias

Las aplicaciones ven el IO en la fila de efectos. Reo podrá decidir su propia
política de paths y merge de catálogos sin que `kai-yaml` adopte configuración
global.
