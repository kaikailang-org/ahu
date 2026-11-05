# Anga

Anga is the background-job library for Kaikai and Manutara. It is inspired by
[Active Job](https://api.rubyonrails.org/classes/ActiveJob.html): it defines a
stable contract between jobs and queue backends, expressed through immutable
data, `Result`, explicit dispatch, and Kaikai effects.

Anga 0.1 includes:

- validated `Spec` and `Job` values;
- portable arguments represented as `[JsonValue]`;
- queues, priorities, and absolute or relative scheduling;
- `perform_now`, `perform_later`, `perform_at`, and `perform_in`;
- a replaceable `QueueAdapter` effect;
- `enqueue` and `enqueue_at`, plus degradable bulk submission with `submit_all`;
- a canonical JSON codec for future adapters;
- an in-memory adapter with priority, FIFO ordering, queue filters, and history;
- an explicit dispatcher, without reflection or global configuration.

## Dependency

```toml
[dependencies]
anga = { path = "../anga" }
```

Anga does not depend on Manutara. A web application can import it without
coupling the job core to HTTP.

## Define a job

A job is an ordinary specification. The worker name is stable, and its
arguments must be able to cross a JSON boundary:

```kai
import encoding.json

import anga.job

fn welcome_email(user_id: String) : Result[job.Spec, job.JobError] = {
  let base = job.new("mail.welcome", [JStr(user_id)])!
  let queued = job.on_queue(base, "mailers")!
  job.with_priority(queued, 5)
}
```

A lower priority integer runs first within the same queue selection. Jobs with
the same priority preserve FIFO order.

## Application dispatcher

Kaikai does not serialize closures or discover modules through reflection. The
application exhaustively maps a worker name to a function:

```kai
import encoding.json

fn dispatch(worker: String, arguments: [JsonValue]) : Result[Unit, String] / File + Process = match worker {
  "mail.welcome" -> perform_welcome(arguments)
  "reports.generate" -> perform_report(arguments)
  _ -> Err("unknown worker: #{worker}")
}
```

When renaming a worker, temporarily keep an alias in this dispatcher so old
documents can still run.

## Run now

```kai
let result = anga.perform_now(spec, dispatch)
# Result[execution.Record, job.JobError]
# / Clock + SecureRandom + dispatcher effects
```

`perform_now` does not touch a queue. It materializes the job, increments the
execution counter, and returns `Succeeded` or `Failed(message)` as data.

## Enqueue

```kai
let queued = anga.perform_later(spec)
# Result[anga.Enqueued, anga.EnqueueError]
# / Clock + SecureRandom + QueueAdapter
```

For scheduling:

```kai
anga.perform_at(spec, time.WallTime { secs: 1_800_000_000, nanos: 0 })
anga.perform_in(spec, time.minutes(15))
```

The function selects `enqueue` or `enqueue_at` based on the `Job`. The backend
returns a receipt containing its name and the accepted ID.

## In-memory adapter

The adapter does not maintain a singleton. It receives state and returns the
new state:

```kai
import anga
import anga.adapters.memory

let run = memory.with_adapter(memory.empty(), () => {
  anga.perform_later(spec)
})

let enqueue_result = run.value
let queue_state = run.state
```

`with_adapter` removes `QueueAdapter` from the body's effect row and forwards
its other effects, such as `Clock` and `SecureRandom`.

The application decides when to run ready jobs:

```kai
let next = memory.perform_next(queue_state, time.now(), ["mailers"], dispatch)
let drained = memory.drain_ready(next.state, time.now(), ["mailers"], dispatch)
```

An empty queue list selects all queues. Future jobs remain pending, and
duplicate IDs are rejected without changing the state.

## Adapter selection

| Adapter | Queue lifetime | Consumer |
| --- | --- | --- |
| Inline | No waiting queue | The adapter executes before acknowledging enqueue |
| Memory | Lifetime of the retained immutable `memory.State` | The owning process calls `perform_next` or `drain_ready` |
| Manutara Solid Queue | Durable SQLite rows | A separate polling worker claims and finalizes jobs |

Inline is an application-specific adapter rather than part of Anga's core;
Manutara Storage provides one that dispatches its analysis and variant workers.
See its [queue adapter guide](../manutara-storage/docs/queue-adapters.md) for
complete inline, memory, and Solid wiring. Solid Queue's durable implementation
is documented in [Manutara Solid Queue](../manutara-solid-queue/README.md).

## Manutara

An action declares the effect in its signature; the adapter is irrelevant:

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

The composition root installs the memory adapter in development or a durable
adapter in production. Controllers and domain code do not change when the
backend changes.

## Queue document

```kai
let document = codec.encode(materialized_job)
let restored = codec.decode(document)
```

The decoder revalidates the ID, worker, queue, priority, timestamps, and
execution counter. A persistent backend should reuse this document.

## Development

```sh
./scripts/check.sh
```

The script checks canonical formatting, typechecking, linting, tests, and
public documentation.

## Memory limitations

The in-memory adapter is ephemeral, manual, and non-concurrent: it loses all
data on restart, does not start workers, and must not be used as a production
backend. This is intentional; it keeps the contract stable and testable before
adding supervision, locking, retries, and persistence.

The architecture and decisions are documented in
[`docs/design.md`](docs/design.md).
