# ADR 0002: workers por nombre y argumentos JSON

Estado: aceptada — 2026-08-12.

## Contexto

Active Job puede serializar objetos mediante serializers y GlobalID. Kaikai no
tiene reflexión de módulos en runtime y una función/closure no es un payload
portable para una cola durable.

## Decisión

Un job contiene el nombre estable del worker y `[JsonValue]`. La aplicación
provee un dispatcher exhaustivo que traduce ese nombre a una función tipada.
`anga.codec` define la representación canónica para adaptadores futuros.

## Alternativas

- Guardar closures: impide persistencia y despliegues con versiones distintas.
- `String` sin estructura para argumentos: traslada parsing e invariantes a
  cada worker.
- Importar Tino: útil para modelos de borde complejos, pero innecesario en el
  contrato base; cada aplicación puede validarlos con Tino antes de encolar.

## Consecuencias

Los límites de serialización son evidentes. Renombrar un worker es un cambio de
compatibilidad que debe acompañarse con un alias en el dispatcher mientras
existan jobs antiguos.
