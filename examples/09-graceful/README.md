# 09 — graceful

`ServerPolicy`'s fluent knobs, `BackgroundTasks` running after the response
is on the wire, and an honest look at what "graceful" covers here today.

By way of: axum's `graceful-shutdown` + `key-value-store` examples.

## Run

```sh
nova build --strict-effects src/main.nv
./main   # binds 0.0.0.0:18090
```

```sh
curl http://localhost:18090/health   # ok
curl http://localhost:18090/policy
# defaults: max_inflight=16 reject_with_503=true max_requests_per_conn=100 max_body_bytes=1048576
# tuned:    max_inflight=64 max_body_bytes=4194304

curl http://localhost:18090/log      # (empty -- hit /work first)
curl http://localhost:18090/work     # queued 1 background task(s)
curl http://localhost:18090/log      # background task ran
```

`/work`'s response goes out to the client *before* its queued task runs —
`/log` only shows the task's effect on the *next* request, proof the work
really happened after the wire write, not before.

## What's real here, and what isn't (read this one)

- **`BackgroundTasks`** is fully real and live: `serve_router`'s own
  connection driver (`polaris.net.serve_connection`) calls `@drain()` right
  after the response bytes are written (see
  [`docs/serving.md`](../../docs/serving.md#background-tasks)).
- **`ServerPolicy`**'s knobs (`max_inflight` admission control, deadlines,
  `max_body_bytes`) are real and live here too: `/policy` above
  *constructs and reads* a standalone one for the printout, but `main()`
  below binds the SAME tuned policy (`max_inflight(64)`) into the real
  `serve_router` accept loop — so what `/policy` reports is exactly what
  governs the live socket, not just illustrative.
- **recover-500** (a caught handler panic answered as a `500` per
  `policy.panic_response()`) is likewise live through the same
  `serve_router`/`serve_connection` accept loop this example's `main()` runs.
- **Graceful shutdown** (draining in-flight background tasks on process
  exit) is **not implemented** anywhere in Polaris yet — see
  [`docs/roadmap.md`](../../docs/roadmap.md#background-task-graceful-shutdown).
  This example's name matches the plan's own canon-list entry; it does not
  claim a shutdown-drain feature that doesn't exist.

## Related documentation

- [`docs/serving.md`](../../docs/serving.md) — `ServerPolicy`, the accept loop, background tasks, streaming
- [`docs/roadmap.md`](../../docs/roadmap.md) — what's planned but not implemented (graceful shutdown, among others)

[Русский](README.ru.md) · see [`examples/README.md`](../README.md) for `main()`'s canonical `serve_router` shape.
