# Polaris examples

Twelve runnable applications, simplest to most complete, each its own
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
| [12](12-https/) | `https` | `serve_tls` + a self-signed cert: TLS termination in front of a `Router` | nova-tls's own `examples/tls/echo_server.nv`, with HTTP on top |

## Building one

```sh
cd 01-hello
nova build --strict-effects src/main.nv
./main
```

Each example's own README has its port and a couple of `curl` calls to try.

## Why every `main()` looks the same shape

Every example's `src/main.nv` carries **one** entry point, the same shape
every doc page teaches (`../docs/overview.md#minimal-server`,
[`../docs/serving.md`](../docs/serving.md)):

```nova
fn main() Net Time Detach -> () {
    ro app = build_router()
    consume listener = TcpListener.bind("0.0.0.0:PORT")!!
    serve_router(listener, app, ServerPolicy.new())
}
```

Bind, then one call to `polaris.serve.serve_router(listener, router, policy)`
— the full accept loop with keep-alive, deadlines, body caps and admission
control, all from `ServerPolicy`. No `supervised { spawn { ... } }` wrapper
around the accept loop: the process' main body runs as its own fiber, so a
blocking `serve_router` call works directly there. `08-websocket-echo` uses
the exact same shape — the `WebSocketUpgrade` hijack hook `serve_router`'s
own connection driver checks after writing the `101` response works without
any hand-rolled accept loop.

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
| 12-https | 18093 |

`12-https` does not follow the shared `main()` shape above (`serve_tls`, not
`serve_router`/`ServerPolicy`) — see that example's own README for why.

[Русский](README.ru.md)
