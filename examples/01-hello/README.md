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

`main()` is the canonical shape [`docs/serving.md`](../../docs/serving.md)/
[`docs/overview.md`](../../docs/overview.md#minimal-server) teach: bind, then
one call to `serve_router(listener, app, ServerPolicy.new())` — the full
accept loop with keep-alive, deadlines, body caps and admission control, all
from `ServerPolicy`. No `supervised { spawn { ... } }` wrapper around it:
`main`'s own body already runs as its own fiber, so the blocking
`serve_router` call works directly here. Every example in this set follows
the same one-function pattern; see the top-level
[`examples/README.md`](../README.md) for the one shared explanation.

## Related documentation

- [`docs/overview.md`](../../docs/overview.md) — this exact server, explained
- [`docs/routing.md`](../../docs/routing.md) — `Router`, path patterns
- [`docs/serving.md`](../../docs/serving.md) — `ServerPolicy`, the accept loop

[Русский](README.ru.md)
