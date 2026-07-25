# nova-polaris

**Polaris** ⭐ — a server web framework for [Nova](https://nv-lang.org): a
segment-trie `Router` (`{param}`/`{*rest}`, `nest`/fallback), typed
extractors, `IntoResponse`, middleware composition + batteries (cors,
compress, log, ratelimit), static-file serving, auth
(Bearer/Basic/JWT/sessions), WebSocket, and a graceful accept-loop server.

**Nova** — the new star; **Polaris** — the one you steer by.

```nova
import polaris.{Router, ServerRequest, ServerResponse}
import polaris.net.{ServerPolicy}
import polaris.serve.{serve_router}
import polaris.{StatusCode}
import std.net.{TcpListener, SocketAddr}

fn main() Net Time Detach -> () {
    mut app = Router.new()
    app.get("/hello/{name}", fn(req ServerRequest) -> ServerResponse {
        ro name = req.param("name") ?? "world"
        ServerResponse.text(StatusCode.OK, "hello, ${name}")
    })!!

    consume listener = TcpListener.bind(SocketAddr.from_str("0.0.0.0:8080")!!)!!
    serve_router(listener, app, ServerPolicy.new())
}
```

This is the exact shape compiled (never run, since it needs a real
listener) as `overview_main` in
[`src/doc_samples_test.nv`](src/doc_samples_test.nv) — see
[`docs/overview.md`](docs/overview.md) for the same server driven
socket-free through `serve_once`, and [`docs/serving.md`](docs/serving.md)
for what `ServerPolicy` buys you.

The protocol core (`Request`/`Response`/`HeaderMap`/`Url` types, HTTP
client, transport) is the [`http`](https://github.com/nv-lang/nova-http)
package: Polaris depends on it, and it arrives transitively for most
Polaris users.

## Examples

[`examples/`](examples/) — ten whole runnable applications, simplest to
most complete, each its own package: `nova build --strict-effects` +
actually run it. See [`examples/README.md`](examples/README.md).

## Documentation

- [`docs/overview.md`](docs/overview.md) — what Polaris is, the minimal
  server above explained, the module map
- [`docs/routing.md`](docs/routing.md) — `Router`, path patterns,
  `MethodRouter`, `nest`, fallbacks
- [`docs/handlers-response.md`](docs/handlers-response.md) —
  `ServerRequest`/`ServerResponse`, `IntoResponse`, typed extractors,
  `StatusCode`
- [`docs/middleware.md`](docs/middleware.md) — writing and composing
  `Middleware`
- [`docs/batteries.md`](docs/batteries.md) — cors, compress, log,
  ratelimit
- [`docs/auth.md`](docs/auth.md) — Bearer/Basic/JWT/cookies/sessions
- [`docs/static-files.md`](docs/static-files.md) — serving
  embedded/on-disk assets
- [`docs/websocket.md`](docs/websocket.md) — the WebSocket upgrade +
  protocol layer
- [`docs/serving.md`](docs/serving.md) — `ServerPolicy`, the accept loop,
  background tasks
- [`docs/errors.md`](docs/errors.md) — `HttpError`, status mapping,
  `?`-ergonomics
- [`docs/roadmap.md`](docs/roadmap.md) — what's planned but not
  implemented yet

Every code sample across this documentation set compiles and runs as part
of [`src/doc_samples_test.nv`](src/doc_samples_test.nv) — `nova test
src/doc_samples_test.nv` is the doc set's own correctness gate.

[Русская версия этого README](README.ru.md).

## Status

The framework layers (`Router`, extractors, middleware, auth, WebSocket,
static files, serving) were extracted out of `nova-http` into this
package (Plan 222); `nova-http` now holds only the protocol core. See the
docs above for the current, code-verified surface, and
[`docs/roadmap.md`](docs/roadmap.md) for what's still ahead.

## License

MIT OR Apache-2.0.
