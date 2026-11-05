# ahu.jobs design

`ahu.jobs` is the background-job contract for ahu applications, Manutara included. It
takes Active Job's separation between job definition and operational backend,
but expresses that separation with immutable data, `Result`, functions, and
explicit effects.

## Goals

- A job has an identity, worker name, serializable arguments, queue, priority,
  and optional execution time.
- The application can enqueue immediately, enqueue for a date, or enqueue a
  batch without knowing the backend.
- An adapter implements only the stable `ahu.jobs` contract.
- The first adapter keeps jobs in memory for development and testing.
- Execution does not use reflection: the application supplies an explicit
  dispatcher.

Persistence, cron, automatic retries, continuations, concurrent worker
processes, and distributed guarantees are not goals for 0.1.

## Architecture

```text
Manutara controller / domain / Tuku
                │
                ▼
          jobs.perform_later
                │
     Clock + SecureRandom + QueueAdapter
                │
                ▼
          ahu.jobs.adapter contract
             enqueue(job)
          enqueue_at(job, at)
                │
                ▼
       ahu.jobs.adapters.memory.State
                │
         pop_ready(now, queues)
                │
                ▼
       ahu.jobs.execution.perform(job, dispatch)
```

Dependencies point toward pure values. The core does not import Manutara, and
Manutara does not need to know a concrete adapter. An action can declare
`QueueAdapter` in its effect row just as it declares `File`, `Clock`, or a
domain capability.

## Domain model

`Spec` is a validated description that does not yet have an identity or enqueue
time. `Job` is the materialized document that crosses the adapter contract.

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

Constructors validate names, queues, and priority. `materialize` generates an
ID with `SecureRandom` and captures the time with `Clock`. Testing and backend
restoration use a deterministic constructor that enforces the same invariants.

Arguments are `[JsonValue]`. A closure or live object cannot be serialized
portably; the worker is identified by name, and an application dispatcher
decides which function to execute.

## Adapter contract

```kai
pub effect QueueAdapter {
  enqueue(job: job.Job) : Result[Receipt, AdapterError]
  enqueue_at(job: job.Job, at: time.WallTime) : Result[Receipt, AdapterError]
}
```

This is the same conceptual minimum as Active Job's `AbstractAdapter`.
Additional capabilities belong to the adapter. `submit_all` is an `ahu.jobs` helper
that degrades correctly to individual calls, so it does not require every
backend to implement a bulk operation.

`perform_later` materializes the `Spec` and selects `enqueue` or `enqueue_at`.
It returns the `Job` and the adapter's accepted receipt inside `Result`.

## In-memory adapter semantics

State is an immutable value:

```kai
type State
type Run[T] = { value: T, state: State }
```

`with_adapter(initial, body)` installs `QueueAdapter`, runs `body`, and returns
its result together with the new state. This avoids global configuration and
makes exactly what happened observable.

The backend maintains a monotonically increasing sequence number. When taking
a job, it:

1. considers only jobs whose `scheduled_at <= now`;
2. limits the selection to the requested queues, or accepts all queues when the
   list is empty;
3. sorts by ascending priority, where a lower integer is more important;
4. breaks ties using FIFO sequence order.

`perform_next` removes a ready job, calls the dispatcher, and records
`Succeeded` or `Failed(message)`. Version 0.1 does not retry automatically.

State lives only in the process and is lost on restart. It is not a concurrent
shared store. It is suitable for tests, development, and manual execution, not
for production.

## Codec

`ahu.jobs.codec` converts a `Job` to canonical `JsonValue` and restores it while
validating the complete document. A future persistent adapter will reuse this
format instead of inventing an incompatible representation.

## Error strategy

- `JobError`: invalid specification or document.
- `AdapterError`: unavailable backend, rejection, or unsupported capability.
- `CodecError`: malformed JSON or an invalid restored job.
- `Outcome.Failed`: the dispatcher ran the job and returned an error.

No recoverable error uses exceptions or bare strings as its primary return
value.

## Manutara integration

```kai
fn create_report(ctx: context.Context) : Response / Clock + SecureRandom + QueueAdapter =
  match job.new("reports.generate", [JStr(context.url(ctx))]) {
    Err(_) -> response.bad_request("invalid job")
    Ok(spec) -> match jobs.perform_later(spec) {
      Err(_) -> response.with_status(response.text("queue unavailable"), 503)
      Ok(_) -> response.with_status(response.text("queued"), 202)
    }
  }
```

The composition root installs the adapter. The action knows only the effect,
so moving from memory to a durable backend does not change the controller.

## Gates

- invariant and scheduling tests;
- contract tests with deterministic handlers;
- priority, FIFO, queue-selection, and execution tests;
- codec round-trip and rejection tests;
- typechecking of every module and fixture through `make tier1`.

## Evolution

1. Shipped: contract, codec, and deterministic in-memory adapter.
2. Next: retry/backoff policies and observable hooks represented as effects.
3. Then: supervised workers; the durable adapter lives with Manutara.
4. Future: native bulk operations, cron, uniqueness, locks, and continuations
   as optional capabilities rather than assumptions in the minimum contract.
