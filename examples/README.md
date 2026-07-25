# Polaris examples

Ten runnable applications, simplest to most complete, each its own
self-contained package depending on `polaris` (and `http` for
`StatusCode`/`HttpError`) by local path. Each one builds `--strict-effects`
and actually runs — start it, hit it with `curl`, stop it — see
[`run_smokes.ps1`](run_smokes.ps1) / [`run_smokes.sh`](run_smokes.sh).

Docs ([`../docs/`](../docs/)) show one idea per snippet; these examples show
how the pieces fit together into a whole small program you can copy as a
starting point.

| # | Example | Shows | By way of |
|---|---|---|---|
| [01](01-hello/) | `hello` | `Router.new` + one `get` + serve | axum `hello-world`, Express hello |
| [02](02-routing/) | `routing` | `{name}`/`{*rest}`, `MethodRouter`, `nest`, fallback-404, path conflicts | axum routing example, chi routing |
| [03](03-json-api/) | `json-api` | REST CRUD (in-memory todos): `req.json[T]`, `ServerResponse.json`, `#impl(Serialize/Deserialize)` | axum `todos`, FastAPI tutorial |
| [04](04-middleware/) | `middleware` | custom `middleware(fn(req, next))`, `@then`, layer ordering, log+ratelimit | axum tower-middleware showcase, Express middleware chain |
| [05](05-auth/) | `auth` | Basic + Bearer/JWT, session cookie, public/private zones via `nest`+`layer` | axum `jwt`, FastAPI OAuth2 tutorial |
| [06](06-static-site/) | `static-site` | `polaris.static` + index fallback, cache headers | axum `static-file-server` |
| [07](07-sse-stream/) | `sse-stream` | `StreamBody` + `sse_event`: a live ticker | axum `sse` |
| [08](08-websocket-echo/) | `websocket-echo` | `WebSocketUpgrade`, `WebSocket.with_limit`, echo loop | axum `websockets` |
| [09](09-graceful/) | `graceful` | `ServerPolicy` limits/admission, `BackgroundTasks`, recover-500 | axum `graceful-shutdown` + `key-value-store` |
| [10](10-mini-service/) | `mini-service` | json-api + auth + middleware stack + static + policy, one service | RealWorld (Conduit) — trimmed profile |

## Building one

```sh
cd 01-hello
nova build --strict-effects src/main.nv
./main
```

Each example's own README has its port and a couple of `curl` calls to try.

## Why every `main()` looks the same shape

Every example's `src/main.nv` carries **two** entry-shaped functions:

- **`main()`** — what actually runs. It drives its own `TcpListener.accept()`
  loop by hand, dispatching each connection through the low-level
  `polaris.serve.handle_connection_router` (documented in
  [`../docs/serving.md`](../docs/serving.md) as the single-shot building
  block `serve_router` is made from), inside one `supervised { spawn { ... } }`
  block — accepting straight on the bootstrap fiber parks invalidly
  (`nova_sched_park: invalid scope/slot`), so the loop has to live inside a
  spawned fiber regardless of which connection driver services it.
- **`production_main()`** — compiled, **never called** (same "compile-only"
  convention `docs/doc_samples_test.nv` uses for anything needing a real
  socket). It shows the *canonical* shape every doc page teaches: bind, then
  one call to `polaris.serve.serve_router(listener, router, ServerPolicy.new())`
  — the full accept loop with keep-alive, deadlines, body caps and admission
  control. In this toolchain snapshot that call fails to **link**
  (`undefined symbol: nova_fn_hook`), isolated (a minimal `detach`/`spawn`
  repro during this wave) to the recover-500 panic-recovery hook
  `serve_router`'s per-request supervision installs — not to anything in
  Polaris' own routing/handler/middleware code, and not present at all when
  driving connections through the lower-level `handle_connection_router`
  used above. Filed for whoever owns the runtime-hook plumbing next; every
  example otherwise runs the real framework code (`Router`, extractors,
  middleware, auth, static files, SSE, WebSocket) for real, over a real
  socket, answering real `curl` requests.

## Ports

Each example binds a distinct, non-standard port (`18081 + NN`) so
`run_smokes` can build and smoke-test every one without collisions:

| Example | Port |
|---|---|
| 01-hello | 18082 |
| 02-routing | 18083 |
| 03-json-api | 18084 |
| 04-middleware | 18085 |
| 05-auth | 18086 |
| 06-static-site | 18087 |
| 07-sse-stream | 18088 |
| 08-websocket-echo | 18089 |
| 09-graceful | 18090 |
| 10-mini-service | 18091 |

[Русский](README.ru.md)
