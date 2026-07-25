# 01 — hello

The smallest possible Polaris server: `Router.new()`, one `.get()`, serve.
Ten lines to a working HTTP endpoint.

By way of: axum's own `hello-world` example, Express's `app.get('/', ...)`.

## Run

```sh
nova build --strict-effects src/main.nv
./main   # binds 0.0.0.0:18082
```

```sh
curl http://localhost:18082/hello/nova
# hello, nova
curl http://localhost:18082/
# hello, world -- try GET /hello/{name}
```

## What to poke at

- Change the `{name}` path param in `build_router()` to a second segment
  (`/hello/{name}/{lang}`) and read both with `req.param(...)`.
- Add a second route returning `StatusCode.OK.into_response()` bodyless, or
  a plain `str` — see `IntoResponse` in the docs below.

## A note on `main()`'s shape

`main()` drives its own `TcpListener.accept()` loop through the low-level
`handle_connection_router` (one request per connection, no keep-alive) inside
a `supervised { spawn { ... } }` block — accepting on the bootstrap fiber
directly parks invalidly (`nova_sched_park: invalid scope/slot`), so the
accept loop always needs to run inside a spawned fiber. `production_main()`
(compiled, never called) shows the *canonical* shape from
[`docs/serving.md`](../../docs/serving.md) — `serve_router` +
`ServerPolicy` (keep-alive, deadlines, admission control) — which currently
fails to *link* in this toolchain snapshot (`undefined symbol: nova_fn_hook`,
traced to the recover-500 panic-hook plumbing `serve_router` builds on, not
to anything in this example or in Polaris' routing/handler code). Every
example in this set follows the same two-function pattern; see the top-level
[`examples/README.md`](../README.md) for the one shared explanation.

## Related documentation

- [`docs/overview.md`](../../docs/overview.md) — this exact server, explained
- [`docs/routing.md`](../../docs/routing.md) — `Router`, path patterns
- [`docs/serving.md`](../../docs/serving.md) — `ServerPolicy`, the accept loop

[Русский](README.ru.md)
