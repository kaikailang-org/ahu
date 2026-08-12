# Diseño de Anga 0.1

Anga es el contrato de trabajos en segundo plano para aplicaciones Kaikai y
Manutara. Toma de Active Job la separación entre la definición del trabajo y
el backend operacional, pero expresa esa separación con datos inmutables,
`Result`, funciones y efectos explícitos.

## Objetivos

- Un trabajo tiene identidad, nombre de worker, argumentos serializables,
  cola, prioridad y tiempo opcional de ejecución.
- La aplicación puede encolar ahora, encolar para una fecha o encolar un lote
  sin conocer el backend.
- Un adaptador implementa solamente el contrato estable de Anga.
- El primer adaptador conserva trabajos en memoria para desarrollo y pruebas.
- La ejecución no usa reflexión: la aplicación entrega un dispatcher explícito.

No son objetivos de 0.1 la persistencia, cron, retries automáticos,
continuations, procesos worker concurrentes ni garantías distribuidas.

## Arquitectura

```text
Manutara controller / dominio / Tuku
                │
                ▼
          anga.perform_later
                │
     Clock + SecureRandom + QueueAdapter
                │
                ▼
          anga.adapter contract
             enqueue(job)
          enqueue_at(job, at)
                │
                ▼
       anga.adapters.memory.State
                │
         pop_ready(now, queues)
                │
                ▼
       anga.execution.perform(job, dispatch)
```

La dirección de dependencias apunta hacia valores puros. El núcleo no importa
Manutara y Manutara no necesita conocer un adaptador concreto. Una action puede
declarar `QueueAdapter` en su fila de efectos exactamente igual que declara
`File`, `Clock` o una capacidad de dominio.

## Modelo de dominio

`Spec` es una descripción validada todavía sin identidad ni hora de encolado.
`Job` es el documento materializado que cruza el contrato del adaptador.

```kai
type Schedule = Immediate | At(time.WallTime)

type Spec

type Job = {
  id: String,
  worker: String,
  arguments: [JsonValue],
  queue: String,
  priority: Int,
  enqueued_at: time.WallTime,
  scheduled_at: Option[time.WallTime],
  executions: Int
}
```

Los constructores validan nombres, colas y prioridad. `materialize` genera un
ID con `SecureRandom` y captura la hora con `Clock`. Para pruebas y restauración
desde un backend existe un constructor determinista que exige los mismos
invariantes.

Los argumentos son `[JsonValue]`. Una closure o un objeto vivo no puede
serializarse de manera portable; el worker se identifica por nombre y un
dispatcher de aplicación decide qué función ejecutar.

## Contrato del adaptador

```kai
pub effect QueueAdapter {
  enqueue(job: job.Job) : Result[Receipt, AdapterError]
  enqueue_at(job: job.Job, at: time.WallTime) : Result[Receipt, AdapterError]
}
```

Este es el mismo mínimo conceptual del `AbstractAdapter` de Active Job. Las
capacidades adicionales pertenecen al adaptador. `submit_all` es un helper de
Anga y degrada correctamente a llamadas individuales, por lo que no obliga a
todos los backends a implementar una operación bulk.

`perform_later` materializa el `Spec` y selecciona `enqueue` o `enqueue_at`.
Devuelve el `Job` y el receipt aceptado por el adaptador dentro de `Result`.

## Semántica del adaptador en memoria

El estado es un valor inmutable:

```kai
type State
type Run[T] = { value: T, state: State }
```

`with_adapter(initial, body)` instala `QueueAdapter`, ejecuta `body` y devuelve
su resultado junto con el nuevo estado. Esto evita configuración global y
permite inspeccionar exactamente lo que ocurrió.

El backend mantiene un número de secuencia monotónico. Al tomar un trabajo:

1. solo considera trabajos cuyo `scheduled_at <= now`;
2. limita por las colas solicitadas, o acepta todas si la lista está vacía;
3. ordena por prioridad ascendente: un entero menor es más importante;
4. desempata por secuencia FIFO.

`perform_next` retira un trabajo listo, llama al dispatcher y conserva un
registro `Succeeded` o `Failed(message)`. 0.1 no reintenta automáticamente.

El estado vive únicamente en el proceso y se pierde al reiniciar. Tampoco es
un almacén compartido concurrente. Es apropiado para tests, desarrollo y
ejecución manual, no para producción.

## Codec

`anga.codec` traduce `Job` a un `JsonValue` canónico y lo restaura validando el
documento completo. Un futuro adaptador persistente reutilizará este formato en
lugar de inventar una representación incompatible.

## Estrategia de errores

- `JobError`: especificación o documento inválido.
- `AdapterError`: backend no disponible, rechazo o capacidad no soportada.
- `CodecError`: JSON mal formado o job inválido al restaurar.
- `Outcome.Failed`: el dispatcher ejecutó el job y devolvió un error.

Ningún error recuperable usa excepciones ni strings desnudos como valor de
retorno principal.

## Integración con Manutara

```kai
fn create_report(ctx: context.Context) : Response / Clock + SecureRandom + QueueAdapter =
  match job.new("reports.generate", [JStr(context.url(ctx))]) {
    Err(_) -> response.bad_request("invalid job")
    Ok(spec) -> match anga.perform_later(spec) {
      Err(_) -> response.with_status(response.text("queue unavailable"), 503)
      Ok(_) -> response.with_status(response.text("queued"), 202)
    }
  }
```

El composition root instala el adaptador. La action solo conoce el efecto, por
lo que migrar desde memoria a un backend durable no cambia el controller.

## Gates

- pruebas de invariantes y scheduling;
- pruebas de contrato con handlers deterministas;
- pruebas de prioridad, FIFO, selección de colas y ejecución;
- round-trip y rechazo del codec;
- formato canónico, typecheck, lint y documentación pública.

## Evolución

1. 0.1: contrato, codec y adaptador en memoria determinista.
2. 0.2: políticas de retry/backoff y hooks observables como efectos.
3. 0.3: workers supervisados y adapter durable.
4. Futuro: bulk nativo, cron, unicidad, locks y continuations como capacidades
   opcionales, no como supuestos del contrato mínimo.
