# Anga

Anga es la librería de background jobs para Kaikai y Manutara. Está inspirada
en [Active Job](https://api.rubyonrails.org/classes/ActiveJob.html): define un
contrato estable entre jobs y backends de colas, pero lo expresa mediante datos
inmutables, `Result`, dispatch explícito y efectos Kaikai.

Anga 0.1 incluye:

- `Spec` y `Job` validados;
- argumentos portables como `[JsonValue]`;
- colas, prioridades y scheduling absoluto o relativo;
- `perform_now`, `perform_later`, `perform_at` y `perform_in`;
- efecto intercambiable `QueueAdapter`;
- `enqueue` y `enqueue_at`, más bulk degradable con `submit_all`;
- codec JSON canónico para adapters futuros;
- adapter en memoria con prioridad, FIFO, filtros de cola e historial;
- dispatcher explícito, sin reflexión ni configuración global.

## Dependencia

```toml
[dependencies]
anga = { path = "../anga" }
```

Anga no depende de Manutara. Una aplicación web puede importarla sin acoplar el
núcleo de jobs a HTTP.

## Definir un job

Un job es una especificación normal. El nombre del worker es estable y sus
argumentos deben poder cruzar una frontera JSON:

```kai
import encoding.json

import anga.job

fn welcome_email(user_id: String) : Result[job.Spec, job.JobError] = {
  let base = job.new("mail.welcome", [JStr(user_id)])!
  let queued = job.on_queue(base, "mailers")!
  job.with_priority(queued, 5)
}
```

Un entero de prioridad menor se ejecuta antes dentro de la misma selección de
colas. Jobs con igual prioridad conservan orden FIFO.

## Dispatcher de aplicación

Kaikai no serializa closures ni busca módulos mediante reflexión. La aplicación
traduce el nombre del worker a una función de manera exhaustiva:

```kai
import encoding.json

fn dispatch(worker: String, arguments: [JsonValue]) : Result[Unit, String] / File + Process = match worker {
  "mail.welcome" -> perform_welcome(arguments)
  "reports.generate" -> perform_report(arguments)
  _ -> Err("unknown worker: #{worker}")
}
```

Al cambiar el nombre de un worker, mantenga temporalmente un alias en este
dispatcher para poder ejecutar documentos antiguos.

## Ejecutar ahora

```kai
let result = anga.perform_now(spec, dispatch)
# Result[execution.Record, job.JobError]
# / Clock + SecureRandom + efectos del dispatcher
```

`perform_now` no toca ninguna cola. Materializa el job, incrementa el contador
de ejecuciones y devuelve `Succeeded` o `Failed(message)` como datos.

## Encolar

```kai
let queued = anga.perform_later(spec)
# Result[anga.Enqueued, anga.EnqueueError]
# / Clock + SecureRandom + QueueAdapter
```

Para scheduling:

```kai
anga.perform_at(spec, time.WallTime { secs: 1_800_000_000, nanos: 0 })
anga.perform_in(spec, time.minutes(15))
```

La función elige `enqueue` o `enqueue_at` según el `Job`. El backend devuelve
un receipt con su nombre y el ID aceptado.

## Adapter en memoria

El adapter no mantiene un singleton. Recibe estado y devuelve el estado nuevo:

```kai
import anga
import anga.adapters.memory

let run = memory.with_adapter(memory.empty(), () => {
  anga.perform_later(spec)
})

let enqueue_result = run.value
let queue_state = run.state
```

`with_adapter` elimina `QueueAdapter` de la fila del body y deja pasar sus otros
efectos, como `Clock` y `SecureRandom`.

La aplicación decide cuándo ejecutar trabajos listos:

```kai
let next = memory.perform_next(queue_state, time.now(), ["mailers"], dispatch)
let drained = memory.drain_ready(next.state, time.now(), ["mailers"], dispatch)
```

Una lista de colas vacía selecciona todas. Los jobs futuros permanecen
pendientes y los IDs duplicados son rechazados sin cambiar el estado.

## Manutara

Una action declara el efecto en su firma; no importa el adapter:

```kai
import encoding.json

import anga
import anga.adapter
import anga.job

import manutara.controller.context
import manutara.response

fn create_report(ctx: context.Context) : Response / Clock + SecureRandom + QueueAdapter =
  match job.new("reports.generate", [JStr(context.url(ctx))]) {
    Err(_) -> response.bad_request("invalid job")
    Ok(spec) -> match anga.perform_later(spec) {
      Err(_) -> response.with_status(response.text("queue unavailable"), 503)
      Ok(_) -> response.with_status(response.text("queued"), 202)
    }
  }
```

El composition root instala memoria durante desarrollo o un adapter durable en
producción. Controllers y dominio no cambian al migrar de backend.

## Documento de cola

```kai
let document = codec.encode(materialized_job)
let restored = codec.decode(document)
```

El decoder revalida ID, worker, cola, prioridad, timestamps y contador de
ejecuciones. Un backend persistente debe reutilizar este documento.

## Desarrollo

```sh
./scripts/check.sh
```

El script verifica formato canónico, typecheck, lint, pruebas y documentación
pública.

## Límites de memoria

El adapter en memoria es efímero, manual y no concurrente: pierde todo al
reiniciar, no inicia workers y no debe usarse como backend de producción. Esto
es intencional; mantiene estable y comprobable el contrato antes de agregar
supervisión, locking, retries y persistencia.

La arquitectura y las decisiones están en [`docs/design.md`](docs/design.md).
