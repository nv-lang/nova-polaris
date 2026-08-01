# Routing

**English** | [Русский](routing.ru.md)

`Router` is a segment-trie (Axum-class): literal segments, `{name}` params,
and a `{*rest}` catch-all, matched by structural precedence — **not**
registration order. Registration itself is fallible: a conflicting route is
a typed `Result`, never a panic.

Spec/design: [Plan 222.1](https://github.com/nv-lang/nova/blob/main/docs/plans/222.1-router-from-scratch.md)
(nova main repo). Source: [`src/server_router.nv`](../src/server_router.nv).

---

## Contents

- [Registering a route](#registering-a-route)
- [Two registration forms: statement and chain](#two-registration-forms-statement-and-chain)
- [Path patterns](#path-patterns)
- [`MethodRouter`: composing methods on one path](#methodrouter-composing-methods-on-one-path)
- [`nest`: prefix-grouped sub-routers](#nest-prefix-grouped-sub-routers)
- [Fallbacks: global 404 vs per-route 405](#fallbacks-global-404-vs-per-route-405)
- [Route conflicts are typed errors](#route-conflicts-are-typed-errors)
- [Related documents](#related-documents)

---

## Registering a route

```nova
test "routing: statement-form registration with !!" {
    mut r = Router.new()
    r.get("/health", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "ok"))!!
    ro wire = serve_once(r, get_req("/health"))
    assert(status_line(wire) == "HTTP/1.1 200 OK")
}
```

`Router.mut @get/@post/@put/@delete/@patch(path, handler)` each return
`Result[Router, HttpError]` — **not** `Result[(), HttpError]`. The `Ok`
payload is the router itself (`Ok(@)`), which is what makes the two
registration forms below both work off the same signature.

A bare `fn`/closure at a `Handler`-expecting position auto-lifts into
`Handler` (`type Handler fn(ServerRequest) -> ServerResponse` — a newtype
over the fn type, not an alias): `r.get(path, fn(req ServerRequest) -> ServerResponse { ... })`
needs no wrapper call. A `Handler` value itself is called directly
(`h(req)`) — see [handlers-response.md](handlers-response.md#handler).

## Two registration forms: statement and chain

Because `Ok`'s payload is the router, registration composes two ways:

```nova
fn chained_routes() -> Result[Router, HttpError] {
    mut r = Router.new()
    r.get("/a", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "a"))?
     .post("/b", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "b"))
}

test "routing: ?-chain inside a Result-returning fn, and !!-chain on an rvalue" {
    ro r1 = chained_routes()!!
    assert(status_line(serve_once(r1, get_req("/a"))) == "HTTP/1.1 200 OK")

    ro r2 = Router.new()
        .get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "x"))!!
        .post("/y", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "y"))!!
    assert(status_line(serve_once(r2, post_req("/y", ""))) == "HTTP/1.1 200 OK")
}
```

- **Statement form** — `r.get(..)!!` on its own line, one call per line. Most
  code in this doc set uses this form; it reads closest to Express/chi.
- **`?`-chain** — inside a function that itself returns `Result[Router, HttpError]`,
  chain registrations with `?` and let the first failure short-circuit the
  whole function.
- **Fluent `!!`-chain on an rvalue** — `Router.new().get(..)!!.post(..)!!` —
  useful for a one-expression router definition (a `const`-like table at the
  top of a module).

Both forms call the exact same `@route`/`@insert_segs` machinery — pick
whichever reads best at the call site.

## Path patterns

```nova
test "routing: {name} path params and {*rest} catch-all" {
    mut r = Router.new()
    r.get("/users/{id}", fn(req ServerRequest) -> ServerResponse {
        ro id = req.param("id") ?? "?"
        ServerResponse.text(StatusCode.OK, "id=${id}")
    })!!
    r.get("/files/{*path}", fn(req ServerRequest) -> ServerResponse {
        ro path = req.param("path") ?? "?"
        ServerResponse.text(StatusCode.OK, "path=${path}")
    })!!

    assert(wire_str(serve_once(r, get_req("/users/42"))).contains("id=42"))
    assert(wire_str(serve_once(r, get_req("/files/a/b/c"))).contains("path=a/b/c"))
}
```

- `{name}` matches exactly one path segment; its decoded value is read via
  `req.param("name")` (see [handlers-response.md](handlers-response.md)).
- `{*name}` is a catch-all — it must be the **last** segment of the pattern
  (a `{*rest}` anywhere else is a registration-time `Err`) — and its value is
  the rejoined, percent-decoded remainder of the path.
- **Precedence is structural**: literal segments win over `{name}`, which
  wins over `{*name}`, with backtracking on a dead end deeper in the trie —
  independent of the order routes were registered in. This matches Axum
  (and Go 1.22's `net/http`), unlike a linear first-match router.

## `MethodRouter`: composing methods on one path

```nova
test "routing: MethodRouter composes get(h).post(h2) on one path, 405+Allow otherwise" {
    mut r = Router.new()
    r.route("/widgets",
        get(fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "list"))
            .post(fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.CREATED, "made")))!!

    assert(status_line(serve_once(r, get_req("/widgets"))) == "HTTP/1.1 200 OK")
    assert(status_line(serve_once(r, post_req("/widgets", ""))) == "HTTP/1.1 201 Created")
    ro wire405 = serve_once(r, "DELETE /widgets HTTP/1.1\r\nHost: x\r\n\r\n".bytes())
    assert(status_line(wire405) == "HTTP/1.1 405 Method Not Allowed")
    assert(wire_str(wire405).contains("allow: GET, POST"))
}
```

`get(h)`/`post(h)`/`put(h)`/`delete(h)`/`patch(h)` are free functions that
start a `MethodRouter` chain (Axum's `get(handler).post(handler2)` shape);
`Router.@route(path, mr)` registers the whole set atomically at one path.
The five `Router.@get`/`@post`/`@put`/`@delete`/`@patch(path, h)` methods used
elsewhere in this doc set are sugar over `@route(path, get(h))` etc. — both
forms end up as the same trie entry.

When the path matches but no registered method does, Polaris answers a
generic `405 Method Not Allowed` with an `Allow: <methods>` header built from
whatever *is* registered on that route — no extra code needed.

## `nest`: prefix-grouped sub-routers

```nova
test "routing: nest merges a sub-router's routes under a prefix" {
    mut api = Router.new()
    api.get("/widgets/{id}", fn(req ServerRequest) -> ServerResponse {
        ro id = req.param("id") ?? "?"
        ServerResponse.text(StatusCode.OK, "widget ${id}")
    })!!

    mut r = Router.new()
    r.nest("/api", api)!!
    assert(wire_str(serve_once(r, get_req("/api/widgets/9"))).contains("widget 9"))
}
```

`r.nest(prefix, sub)` re-registers every one of `sub`'s already-conflict-free
routes onto `r`, under `prefix` — a prefix collision with an existing route
on `r` is (as always) a typed `Err`, not a panic. `sub`'s own `@fallback`
(its per-router 404) is **not** carried over — only the top-level
`Router.@fallback` and per-route `MethodRouter.@fallback` participate; see
[middleware.md](middleware.md#router-use-and-nest) for how `nest`
interacts with `.use()`.

## Fallbacks: global 404 vs per-route 405

```nova
test "routing: Router.fallback (global 404) vs MethodRouter.fallback (per-route 405)" {
    mut r = Router.new()
    r.fallback(fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.NOT_FOUND, "custom 404"))
    mut mr = get(fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "ok"))
    mr.fallback(fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.METHOD_NOT_ALLOWED, "custom 405"))
    r.route("/guarded", mr)!!

    assert(wire_str(serve_once(r, get_req("/missing"))).contains("custom 404"))
    assert(wire_str(serve_once(r, post_req("/guarded", ""))).contains("custom 405"))
}
```

Two distinct hooks, easy to conflate by name:

| Hook | Fires when | Scope |
|---|---|---|
| `Router.mut @fallback(h)` | **no** path in the trie matches at all | global — the whole router's 404 |
| `MethodRouter.mut @fallback(h)` | the path matched but the method didn't | one route's own 405 override |

Neither is set by default: an unset `Router.@fallback` serves a plain
`404 page not found`; an unset `MethodRouter.@fallback` serves the generic
`405 + Allow` shown above.

## Route conflicts are typed errors

```nova
test "routing: a duplicate/conflicting route registration is a typed Err, not a panic" {
    mut r = Router.new()
    r.get("/dup", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "first"))!!
    ro second = r.route("/dup", get(fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "second")))
    assert(match second { Err(_) => true, Ok(_) => false })
}
```

Axum panics on an equivalent conflict at router-build time; Polaris returns
a typed `Err(HttpError)` instead — the deliberate improvement the design
called for. Three conflict shapes are caught: an exact-duplicate path, two
different `{name}` param names claiming the same trie slot, and a
`{*rest}` that isn't the pattern's last segment.

## Related documents

**Full example:** [`examples/02-routing`](../examples/02-routing) — every pattern on this page, running for real.

- [handlers-response.md](handlers-response.md) — `ServerRequest`/`ServerResponse`, reading params, `Handler`
- [middleware.md](middleware.md) — `Router.@use`, and how it interacts with `@nest`
- [errors.md](errors.md) — `HttpError` and how it becomes a wire response
- [`src/server_router.nv`](../src/server_router.nv) — the trie implementation
- [`src/router_test.nv`](../src/router_test.nv) — the full pin-test suite this page's examples are drawn from
