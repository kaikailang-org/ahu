# ADR 0003: memoria es una máquina de estados efímera

Estado: aceptada — 2026-08-12.

## Contexto

El primer adaptador necesita ser simple, reproducible y útil en pruebas. Crear
desde el inicio un scheduler concurrente mezclaría el contrato con decisiones
de supervisión, shutdown, locking y persistencia.

## Decisión

El adaptador en memoria usa un `State` inmutable y un handler stateful lexical.
La aplicación o el test decide cuándo llamar `pop_ready`, `perform_next` o
`drain_ready`.

## Alternativas

- `Ref[State]`: permite identidad compartida, pero introduce `Mutable` y races
  si se comparte entre fibers.
- Actor interno: adecuado para un adapter async posterior, pero agrega ciclo de
  vida y coordinación antes de estabilizar el contrato.
- Ejecutar inline al encolar: no prueba scheduling ni representa una cola.

## Consecuencias

La implementación es determinista y fácil de testear. No sobrevive reinicios,
no ejecuta sola y no ofrece garantías de concurrencia; esos límites forman
parte explícita de su API y documentación.
