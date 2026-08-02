# Polaris overview

**English** | [Русский](overview.ru.md)

Polaris is a server web framework for [Nova](https://nv-lang.org): a segment-trie
`Router` with `{param}`/`{*rest}` patterns and Axum-style method composition,
typed extractors (`FromRequest`), a single `IntoResponse` convergence point for
handler return values, chi-style middleware composition, a small set of
ready-made "batteries" (CORS, compression, logging, rate-limiting), auth
building blocks (Bearer/Basic/JWT/sessions), a WebSocket layer, static-file
serving, and a graceful accept-loop server (`ServerPolicy`).

If you know [Axum](https://github.com/tokio-rs/axum) or
[FastAPI](https://fastapi.tiangolo.com/), most of this will feel familiar —
Polaris deliberately borrows their shapes where Nova's type system and
effect-based concurrency model allow it, and is explicit (typed `Result`
instead of a panic, no hidden `State<T>` injection) where it doesn't.

## Relationship to `http`

The wire-level protocol — `Request`/`Response`/`HeaderMap`/`Url`/`StatusCode`/
`HttpError`, the HTTP **client**, and the raw transport — lives in the
separate [`http`](https://github.com/nv-lang/nova-http) package (the "core").
Polaris depends on it and re-exposes its error/status types through the
handler surface; a Polaris user typically never imports `http` directly
(it arrives transitively), except to name `StatusCode`/`HttpError` in a
handler's own signature, exactly as the examples below do.

Axum sits on top of `hyper` the same way Polaris sits on top of `http` — the
core owns bytes-on-the-wire, Polaris owns routing/handlers/middleware/serving.

## Minimal server

```nova
test "overview: minimal handler, routed and served without a socket" {
    mut app = Router.new()
    app.get("/hello/{name}", fn(req ServerRequest) -> ServerResponse {
        ro name = req.param("name") ?? "world"
        ServerResponse.text(StatusCode.OK, "hello, ${name}")
    })!!

    ro wire = serve_once(app, get_req("/hello/nova"))
    assert(status_line(wire) == "HTTP/1.1 200 OK")
    assert(wire_str(wire).contains("hello, nova"))
}
```

`serve_once` is the **pure** request→response driver — it takes raw bytes in,
gives raw bytes out, with no socket involved (`http`'s own D361 "mock-first"
discipline: the whole routing/handler/middleware pipeline is exhaustively
testable without ever binding a port). That is exactly what the test above
does, and exactly what `nova test` runs for every example in this doc set —
see [`src/doc_samples_test.nv`](../src/doc_samples_test.nv).

A real process instead binds a `TcpListener` and calls `polaris.serve.serve_router`
(full doc: [serving.md](serving.md)):

```nova
fn overview_main() Net Time Detach -> () {
    mut app = Router.new()
    app.get("/hello/{name}", fn(req ServerRequest) -> ServerResponse {
        ro name = req.param("name") ?? "world"
        ServerResponse.text(StatusCode.OK, "hello, ${name}")
    })!!

    consume listener = TcpListener.bind("0.0.0.0:8080")!!
    serve_router(listener, app, ServerPolicy.new())
}
```

This function is compile-checked (not run) by `doc_samples_test.nv`'s own
`overview_main` — it needs a real socket, so it can't live inside a `test { }`
block; see [serving.md](serving.md) for what `ServerPolicy` actually buys you
(keep-alive, deadlines, body-size caps, admission control) over the bare
`Net`/`Time`/`Detach` effect row it declares.

## Module map

| Module | What it holds |
|---|---|
| `polaris` (root) | `Router`/`MethodRouter`, `ServerRequest`/`ServerResponse`, `Handler`, `Middleware`, `IntoResponse`/`Json[T]`, extractors (`PathParam[T]`/`Query[T]`/`Bytes`/`Text`/`Headers`/`Multipart`), auth (`Bearer`/`BasicAuth`/`JwtAuth`/sessions), `BackgroundTasks`, streaming/SSE, `WebSocketUpgrade`, the pure `serve_once`/`route_once` drivers |
| `polaris.ws` | The RFC 6455 WebSocket protocol layer: frame codec, handshake, the live `WebSocket` connection object |
| `polaris.net` | `ServerPolicy` and the live accept-loop primitives (`serve`, `serve_connection`, `handle_connection`) that take a byte-level callback |
| `polaris.serve` | `serve_router`/`handle_connection_router` — the `Router`-taking convenience wrappers over `polaris.net` |
| `polaris.static` | Static-file serving (`Static` config, `serve_path`, `static_handler`) |
| `polaris.middleware.cors` / `.compress` / `.log` / `.ratelimit` | The batteries — each its own module, each built on the `polaris.middleware(...)` core |

Why the split into `polaris.net`/`polaris.serve` for the wire runner: the
wire layer (`polaris.net`, accept loop, deadlines, keep-alive) must never
import `Router`/routing (a lower layer never depends on a higher one) — it
takes a plain `fn([]u8) -> ServerResponse` callback instead.
`polaris.serve.serve_router` is the thin `Router`-aware wrapper most
applications actually call. See [serving.md](serving.md).

## Contents of this doc set

- [routing.md](routing.md) — `Router`, path patterns, `MethodRouter`, nesting, fallbacks
- [handlers-response.md](handlers-response.md) — `ServerRequest`/`ServerResponse`, `IntoResponse`, extractors, `StatusCode`
- [middleware.md](middleware.md) — writing and composing `Middleware`
- [batteries.md](batteries.md) — cors, compress, log, ratelimit
- [auth.md](auth.md) — Bearer/Basic/JWT/cookies/sessions
- [static-files.md](static-files.md) — serving embedded/on-disk assets
- [websocket.md](websocket.md) — the WebSocket upgrade + protocol layer
- [serving.md](serving.md) — `ServerPolicy`, the accept loop, background tasks
- [errors.md](errors.md) — `HttpError`, status mapping, `?`-ergonomics
- [roadmap.md](roadmap.md) — what is planned but not implemented yet

## Related documents

**Full example:** [`examples/01-hello`](../examples/01-hello) — this exact server, running for real; see [`examples/README.md`](../examples/README.md) for the full set, simplest to most complete.

- [`README.md`](../README.md) — package pitch + install
- [`src/doc_samples_test.nv`](../src/doc_samples_test.nv) — every code sample
  in this doc set, compiled and run by `nova test`
- [nova-http](https://github.com/nv-lang/nova-http) — the core `Request`/
  `Response`/client/transport package Polaris depends on
