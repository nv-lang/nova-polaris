# Serving: `ServerPolicy`, the accept loop, background tasks

**English** | [Русский](serving.ru.md)

This page covers what happens **around** a `Router` once you have one:
binding a socket and running the accept loop, the knobs that make that loop
production-shaped (keep-alive, deadlines, body caps, admission control),
streaming/SSE responses, and FastAPI-`BackgroundTasks`-style deferred work.

Source: [`src/net/serve.nv`](../src/net/serve.nv),
[`src/net/config.nv`](../src/net/config.nv), [`src/net/servernet.nv`](../src/net/servernet.nv),
[`src/serve/serve.nv`](../src/serve/serve.nv), [`src/background.nv`](../src/background.nv).

---

## Contents

- [Layers: `polaris.net` vs `polaris.serve`](#layers-polarisnet-vs-polarisserve)
- [`ServerPolicy`](#serverpolicy)
- [Running the accept loop](#running-the-accept-loop)
- [Streaming and SSE](#streaming-and-sse)
- [Background tasks](#background-tasks)
- [Related documents](#related-documents)

---

## Layers: `polaris.net` vs `polaris.serve`

The wire layer (`polaris.net` — accept loop, keep-alive, deadlines, body-size
cap, chunked decode) **never** imports `Router`/routing (a lower layer never
depends on a higher one) — `serve`/`serve_connection`/`handle_connection`
there take a plain `fn([]u8) -> ServerResponse` byte-level callback instead.
`polaris.serve.serve_router`/`.handle_connection_router` are the thin
`Router`-taking convenience wrappers almost every application actually
calls — the ones used throughout this doc set.

## `ServerPolicy`

```nova
test "serving: ServerPolicy documented defaults + fluent tuning" {
    ro p = ServerPolicy.new()
    assert(p.max_inflight() == 16)
    assert(p.reject_with_503() == true)
    assert(p.max_requests_per_conn() == 100)
    assert(p.max_body_bytes() == 1048576)

    mut q = ServerPolicy.new()
    q.max_inflight(64).max_body_bytes(4 * 1024 * 1024)
    assert(q.max_inflight() == 64)
    assert(q.max_body_bytes() == 4194304)
}
```

Every accept-loop/connection knob lives on one fluent `value` record:

| Knob | Default | Meaning |
|---|---|---|
| `max_inflight` | 16 | connections handled concurrently before admission rejects |
| `reject_with_503` | `true` | an over-budget accept gets a real `503` (vs. a bare close) |
| `max_requests_per_conn` | 100 | requests served on one keep-alive connection before forced `Connection: close` |
| `header_deadline` / `read_deadline` | 5s / 5s | slowloris mitigation — header block / body read, each its own window |
| `idle_deadline` | 60s | how long an open keep-alive connection may sit idle |
| `max_body_bytes` | 1 MiB | request body cap — exceeding it is `413`, never an unbounded buffer grow |
| `max_multipart_parts`/`_part_size`/`_total_bytes` | 256 / 8 MiB / 32 MiB | forwarded to `Multipart.from_request`, see [handlers-response.md](handlers-response.md#multipartform-data) |
| `panic_response` | `InternalError500` | what a caught handler panic answers with |

Every field has a `@x()` getter and a fluent `mut @x(v) -> @` setter — chain
several on one `mut` binding, as `q` does above.

## Running the accept loop

```nova
fn serving_main(consume listener TcpListener, consume single TcpStream, app Router) Net Time Detach -> () {
    serve_router(listener, app, ServerPolicy.new())
    ro _ = handle_connection_router(single, app)
}
```

- **`serve_router(listener, router, policy)`** — the reusable accept loop:
  bind once, `detach` a fiber per accepted connection (bounded-concurrent,
  admission-gated by `max_inflight` via a `Semaphore`), each connection
  loops reading governed requests (`ServerPolicy`'s deadlines/body-cap/
  chunked-decode already applied) and serving them keep-alive. A transient
  `accept()` error backs off briefly and keeps looping rather than taking
  the whole server down; an over-admission accept optionally answers a real
  `503` (`policy.reject_with_503()`). Needs `Net`, `Time` (for the
  deadlines), and `Detach` (it spawns orphan fibers per connection).
- **`handle_connection_router(stream, router)`** — single-shot
  `Connection: close`, one request per already-accepted connection. No
  keep-alive/deadlines/policy — the low-level building block `serve_router`
  is built from, useful when you already own the accept loop yourself (a
  test harness, an embedding host).

A caught handler panic is answered per `policy.panic_response()`
(`InternalError500` by default — an honest `500`, keeping the connection
alive for the *next* request if both sides had agreed to keep-alive) and
logged via `policy.panic_emit`/`@panic_sink(f)` (stdout by default,
redirectable — same recipe as `Log`'s own `@sink`, [batteries.md](batteries.md#log)).

See [`overview.md`](overview.md#minimal-server) for the minimal end-to-end
`main()` this function's own doc-comment abbreviates.

## Streaming and SSE

```nova
test "serving: SSE — text/event-stream headers + event/data framing" {
    mut r = Router.new()
    r.get("/events", fn(req ServerRequest) -> ServerResponse {
        ro chunks [][]u8 = [sse_event("tick", "1"), sse_event("done", "bye")]
        ServerResponse.sse(StreamBody.from_chunks(chunks))
    })!!
    ro wire = serve_once(r, get_req("/events"))
    ro s = wire_str(wire)
    assert(s.contains("content-type: text/event-stream"))
    assert(s.contains("event: tick\ndata: 1\n\n"))
    assert(s.ends_with("0\r\n\r\n"))
}
```

`ServerResponse.stream(status, headers, producer)` builds a
`Transfer-Encoding: chunked` response for any body whose total length isn't
known ahead of time; `.sse(producer)` is the `text/event-stream`
specialization (sets the standard no-cache headers). `StreamBody` is a pull
source — `stream_body(f)` wraps a closure returning `Option[[]u8]` (`None` =
end of stream; the body may block the calling fiber, e.g. a `ChanReader.recv()`
loop, which under the M:N runtime parks only that connection's fiber, not
the whole event loop); `StreamBody.from_chunks(list)` (used above) is the
convenience form over a pre-built, finite chunk list. `sse_event(event, data)`
formats one SSE wire event.

The live socket writer pushes each chunk with its own `write_all` — true
incremental delivery, with write-backpressure coming for free from the
existing `Net.write` park-on-full-buffer behavior (no bespoke flow-control
mechanism). `serve_once` (used in the test above, and everywhere else in
this doc set) fully **drains** the producer into one buffer instead — the
resulting wire bytes are byte-identical to what a live client receives, just
materialized eagerly rather than pushed incrementally, which is exactly what
makes it usable in a socket-free test.

## Background tasks

```nova
test "serving: BackgroundTasks run AFTER the response, in FIFO order" {
    mut order []int = []
    mut bg = BackgroundTasks.new()
    bg.add(|| { order.push(1) })
    bg.add(|| { order.push(2) })
    assert(bg.task_count() == 2)
    bg.drain() // the connection driver calls this once the response bytes are on the wire
    assert(order.len() == 2)
    assert(order[0] == 1)
    assert(order[1] == 2)
}
```

FastAPI's `BackgroundTasks`, built as pure composition of `spawn`/`supervised`
— no new runtime primitive. `bg.add(task)` queues a `fn() -> ()`, FIFO;
`resp.background(bg)` (a `mut @background(tasks) -> @` fluent setter on
`ServerResponse`) attaches the collector to a response. The connection
driver (`handle_connection`/`serve_connection`) calls `@drain()` **after**
the response bytes are fully written to the client — queued work never adds
handler latency. Tasks run **one at a time**, each in its own `supervised`
scope: a panicking task is contained (logged via `@sink(f)`, stdout by
default), does not stop tasks queued after it, and does not crash the
process.

## Related documents

- [handlers-response.md](handlers-response.md) — `ServerResponse`, the value `serve_router` ultimately writes
- [errors.md](errors.md) — how a caught panic and `HttpError`s differ in shape
- [roadmap.md](roadmap.md) — the graceful-shutdown deadline-drain for background tasks (not wired yet)
- [`src/net/`](../src/net), [`src/serve/serve.nv`](../src/serve/serve.nv), [`src/background.nv`](../src/background.nv), [`src/background_test.nv`](../src/background_test.nv)
