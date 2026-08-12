# ADR 0001: QueueAdapter es un efecto

Estado: aceptada — 2026-08-12.

## Contexto

Anga debe permitir cambiar de backend sin que controllers, mailers o dominio
importen implementaciones concretas. Kaikai hace visibles los efectos en la
firma de cada función.

## Decisión

El contrato público será el efecto `QueueAdapter` con las operaciones mínimas
`enqueue` y `enqueue_at`. El backend se instala léxicamente en el composition
root; no habrá registro global de adaptadores.

## Alternativas

- Pasar un record de funciones: explícito, pero repite plumbing y las closures
  no son serializables.
- Configuración global por nombre: familiar en Rails, pero oculta el efecto,
  dificulta tests paralelos y no es idiomática en Kaikai.
- Protocolos: los protocolos actuales son puros y no admiten una fila de
  efectos dependiente de la implementación.

## Consecuencias

Las firmas muestran cuándo una operación encola trabajo y los tests pueden
instalar handlers deterministas. Los adaptadores con IO exponen sus propios
efectos al instalar el handler.
