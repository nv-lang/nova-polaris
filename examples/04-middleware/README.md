# 04 — middleware

A custom `middleware(fn(req, next))`, `@then` composition, layer ordering
(first `.layer()` = outermost), `nest` + `.layer()` interaction, and two
batteries (`log`, `ratelimit`).

By way of: axum's tower-middleware showcase, Express's middleware chain.

## Run

```sh
nova build --strict-effects src/main.nv
./main   # binds 0.0.0.0:18085
```

```sh
curl -D - http://localhost:18085/x | grep -i x-order
# x-order: A,B                      -- .layer(A); .layer(B) -> request flow A -> B -> handler

curl -D - http://localhost:18085/composed/y | grep -i x-order
# x-order: A,B,C,D                  -- nested router: parent's A,B wrap OUTSIDE the sub-router's own C.then(D)

curl -o /dev/null -w '%{http_code}\n' http://localhost:18085/rl/limited   # 200 (burst 1/2)
curl -o /dev/null -w '%{http_code}\n' http://localhost:18085/rl/limited   # 200 (burst 2/2)
curl -D - http://localhost:18085/rl/limited | grep -iE 'HTTP|retry-after'
# HTTP/1.1 429 Too Many Requests
# retry-after: 1
```

Every request also prints one `log` line to stdout (method, path, status,
body size, duration).

## What to poke at

- Add a third `.layer()` call and watch the `x-order` header grow.
- Swap `tag_layer("A").then(tag_layer("B"))` for two separate `.layer()`
  calls — same resulting order, see [`docs/middleware.md`](../../docs/middleware.md#then-composing-two-middlewares).
- Add your own middleware that short-circuits (returns a response without
  calling `next` at all) — an API-key check, say.

## Related documentation

- [`docs/middleware.md`](../../docs/middleware.md) — the canon `middleware(...)` form, `@then`, `nest`+`.layer()`
- [`docs/batteries.md`](../../docs/batteries.md) — `log`, `ratelimit`, plus `cors`/`compress`

[Русский](README.ru.md) · see [`examples/README.md`](../README.md) for `main()`'s canonical `serve_router` shape.
