# 07 — sse-stream

A live ticker over Server-Sent Events, driven by a **pull-based** producer
(`stream_body(fn() -> Option[[]u8])`) rather than a pre-built finite chunk
list — the closure is called once per chunk, `None` ends the stream.

By way of: axum's `sse` example.

## Run

```sh
nova build --strict-effects src/main.nv
./main   # binds 0.0.0.0:18088
```

```sh
curl http://localhost:18088/events
# event: tick
# data: 5
#
# event: tick
# data: 4
# ...
# event: done
# data: bye
```

Over a real socket the connection driver writes each `event:`/`data:` chunk
as its own `write_all` the moment the producer yields it — true incremental
delivery (see [`docs/serving.md`](../../docs/serving.md#streaming-and-sse)).
`curl` above just prints the fully-drained response since the ticker here
has no artificial delay between ticks (see "what to poke at").

## What to poke at

- The `ticker` closure is deliberately effect-free (`fn() -> Option[[]u8]`,
  no `Time`/`Net` in its signature — the type `stream_body` expects). A real
  slow ticker instead blocks the producing fiber on something with a real
  effect, e.g. a `ChanReader.recv()` fed by a separate `spawn`ed timer fiber
  — see the note in `docs/serving.md`'s streaming section for the shape.
- Change `sse_event`'s `event` name per tick (`"tick-${n}"`) and watch the
  client-side `EventSource` API (in a browser) dispatch to different
  listener names.

## Related documentation

- [`docs/serving.md`](../../docs/serving.md#streaming-and-sse) — `StreamBody`, `stream_body`, `sse_event`, the live-socket vs `serve_once` distinction

[Русский](README.ru.md) · see [`examples/README.md`](../README.md) for `main()`'s canonical `serve_router` shape.
