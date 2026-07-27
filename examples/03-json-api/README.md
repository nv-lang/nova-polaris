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
curl -X POST -H 'Content-Type: application/json' -d '{"text":"call back"}' 'http://localhost:18084/todos/1/note?pinned=true'
# noted id=1 pinned=true text=call back
curl http://localhost:18084/openapi.json
# {"openapi":"3.0.3", ...} — see openapi.golden.json for the full doc
```

`POST /todos/{id}/note` is the canon Plan 222.8 §1.3 **bundle** shape: ONE
record (`AddNoteReq`, `src/main.nv`) whose FIELDS are three DIFFERENT
extractor wrappers side by side — `PathParam[TodoIdParam]` (which todo),
`Query[NoteQuery]` (pin it?), `Json[NoteBody]` (the note text) — decoded by
a hand-composed `#impl(FromRequest)` that reads each field in turn and
short-circuits on the first `Err` (see `AddNoteReq.from_request`). Until
2026-07-27 this shape didn't compile at all (registry №139,
`[M-user-generic-value-type-as-struct-field]`); it's registered via
`Router.@post_typed`/`TypedRoute` alongside the plain CRUD routes above,
with `req_shape`/`resp_shape` left `None` (see that call site's own comment
for why — a SEPARATE, still-open compiler gap in the `Reflect` auto-derive
for bundle fields, found while wiring this route up).

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
