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

- **`BackgroundTasks`** is fully real and live: `handle_connection`'s own
  connection driver — used by every example in this set, including this
  one's `main()` — calls `@drain()` right after the response bytes are
  written, exactly as the full `serve_router` accept loop would (see
  [`docs/serving.md`](../../docs/serving.md#background-tasks)).
- **`ServerPolicy`**'s knobs (`max_inflight` admission control, deadlines,
  `max_body_bytes`) are real and documented, but `/policy` above only
  *constructs and reads* one — it is never bound to a live listener in this
  example, because `serve_router` (the accept loop that actually enforces
  it) doesn't link in this toolchain snapshot — see
  [`examples/README.md`](../README.md). `production_main()` (compiled,
  never called) shows exactly how a real `ServerPolicy` gets wired in.
- **recover-500** (a caught handler panic answered as a `500` per
  `policy.panic_response()`) needs the same `serve_router`/`serve_connection`
  path — not exercised live here for the same reason.
- **Graceful shutdown** (draining in-flight background tasks on process
  exit) is **not implemented** anywhere in Polaris yet — see
  [`docs/roadmap.md`](../../docs/roadmap.md#background-task-graceful-shutdown).
  This example's name matches the plan's own canon-list entry; it does not
  claim a shutdown-drain feature that doesn't exist.

## Related documentation

- [`docs/serving.md`](../../docs/serving.md) — `ServerPolicy`, the accept loop, background tasks, streaming
- [`docs/roadmap.md`](../../docs/roadmap.md) — what's planned but not implemented (graceful shutdown, among others)

[Русский](README.ru.md) · see [`examples/README.md`](../README.md) for why `main()`/`production_main()` come in a pair.
