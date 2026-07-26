# 03 — json-api

REST CRUD over an in-memory todo list: typed `Json[T]` extraction on the way
in, `ServerResponse.json`/the `Serialize` blanket on the way out,
`#impl(Serialize + Deserialize)` on the domain type, `HttpError`/`StatusCode`
for the not-found/bad-input paths.

By way of: axum's `todos` example, the FastAPI tutorial's items CRUD.

## Run

```sh
nova build --strict-effects src/main.nv
./main   # binds 0.0.0.0:18084
```

```sh
curl http://localhost:18084/todos
# []
curl -X POST -H 'Content-Type: application/json' -d '{"title":"buy milk"}' http://localhost:18084/todos
# {"title":"buy milk","done":false,"id":1}
curl http://localhost:18084/todos
# [{"id":1,"title":"buy milk","done":false}]
curl http://localhost:18084/todos/1
# {"title":"buy milk","done":false,"id":1}
curl -X PUT -H 'Content-Type: application/json' -d '{"title":"buy milk","done":true}' http://localhost:18084/todos/1
# {"title":"buy milk","done":true,"id":1}
curl -X DELETE http://localhost:18084/todos/1     # 204
curl http://localhost:18084/todos/99              # 404, structured HttpError JSON body
```

## What to poke at

- Add a `GET /todos?done=true` filter reading `req.query_param("done")`.
- Add a `PATCH /todos/{id}` that only updates the fields present in the body
  (today's `PUT` here replaces both `title`/`done` unconditionally).

## One thing this example works around

- **Two-or-more independent same-path route registrations that each close
  over the same outer mutable state** crash at startup (a minimal repro was
  isolated during this wave). Every path on this page that carries more than
  one HTTP method (`/todos`: GET+POST, `/todos/{id}`: GET+PUT+DELETE) is
  therefore registered as one explicit `MethodRouter` chain
  (`get(h).post(h2)`) rather than separate `.get()`/`.post()` calls — the
  same handlers, just chained. [`02-routing`](../02-routing/) uses the plain
  per-call form throughout and needs no such workaround (its handlers don't
  share mutable state across methods on one path).

Filed for the compiler/runtime owner; it doesn't reflect anything about
Polaris' own routing/handler/JSON API, which this example otherwise exercises
for real. (Collection serialization — `GET /todos` returning `Vec[Todo]`
directly via `ServerResponse.json` — used to need a hand-built-JSON
workaround here for an open codegen gap, nova/221.1 №111; that gap is closed,
so every endpoint on this page now goes through the real `Serialize` derive
uniformly, individual `Todo` and `Vec[Todo]` alike.)

## Related documentation

- [`docs/handlers-response.md`](../../docs/handlers-response.md) — `Json[T]`, `IntoResponse`, `StatusCode`
- [`docs/errors.md`](../../docs/errors.md) — `HttpError`, the `Result[T, HttpError]` blanket
- [`docs/routing.md`](../../docs/routing.md) — `MethodRouter`

[Русский](README.ru.md) · see [`examples/README.md`](../README.md) for `main()`'s canonical `serve_router` shape.
