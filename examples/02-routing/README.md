# 02 — routing

`{name}`/`{*rest}` path patterns, `MethodRouter` (`get(h).post(h2)` on one
path), `nest`, a global 404 vs a per-route 405 fallback, and a route conflict
caught as a typed `Err` at startup instead of a panic.

By way of: axum's `routes-and-handlers-close-together`, chi routing.

## Run

```sh
nova build --strict-effects src/main.nv
./main   # binds 0.0.0.0:18083
```

```sh
curl http://localhost:18083/users/42                # user 42
curl http://localhost:18083/files/a/b/c             # path=a/b/c  ({*rest} catch-all)
curl http://localhost:18083/widgets                 # list           (MethodRouter GET)
curl -X POST http://localhost:18083/widgets         # created        (MethodRouter POST)
curl -X DELETE http://localhost:18083/widgets       # 405 + Allow: GET, POST
curl http://localhost:18083/api/widgets/9           # widget 9       (nested under /api)
curl -X DELETE http://localhost:18083/api/guarded   # custom 405: guarded
curl http://localhost:18083/missing                 # custom 404: nothing here
```

The startup log also prints the outcome of registering `/widgets` a second
time — a typed `Err`, never a crash.

## What to poke at

- Add a third `{*deep}` catch-all under a different prefix and see the
  structural-precedence rule (literal > `{name}` > `{*name}`) pick the right
  route regardless of registration order.
- Register the same path twice with two *different* `{name}` names
  (`{id}` vs `{slug}`) — also a conflict, caught the same way.

## Related documentation

- [`docs/routing.md`](../../docs/routing.md) — the full page this example draws from
- [`docs/handlers-response.md`](../../docs/handlers-response.md) — `Handler`, `req.param`

[Русский](README.ru.md) · see [`examples/README.md`](../README.md) for why `main()`/`production_main()` come in a pair.
