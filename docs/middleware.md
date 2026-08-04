# Middleware

**English** | [Русский](middleware.ru.md)

`Middleware` wraps a `Handler` into a new `Handler` — Go/[chi](https://github.com/go-chi/chi)'s
`func(http.Handler) http.Handler`, one-to-one. Tower's generic `Service`
(poll_ready/backpressure) is deliberately **not** ported: Nova's fiber model
has no async-readiness signal to speak of, and backpressure already lives at
the accept loop (`ServerPolicy.max_inflight` — see [serving.md](serving.md)).

Source: [`src/middleware.nv`](../src/middleware.nv).

---

## Contents

- [The canon form: `middleware(fn(req, next))`](#the-canon-form-middlewarefnreq-next)
- [`Router.@use` and ordering](#routeruse-and-ordering)
- [`@then`: composing two middlewares](#then-composing-two-middlewares)
- [Router `@use` and `@nest`](#router-use-and-nest)
- [What gets wrapped](#what-gets-wrapped)
- [Writing your own — batteries style](#writing-your-own--batteries-style)
- [Related documents](#related-documents)

---

## The canon form: `middleware(fn(req, next))`

```nova
export fn middleware(f fn(ServerRequest, Handler) -> ServerResponse) -> Middleware
```

Build a middleware from **one flat closure** — no nested
`fn(next) -> Handler` ceremony. `next` is a plain `Handler` value: call it
directly (`next(req)`), run code before/after it, or short-circuit by
returning your own response without calling it at all.

```nova
fn add_tag(tag str, next Handler, req ServerRequest) -> ServerResponse {
    mut resp = next(req)
    ro prev = hdr(resp, "x-order")
    // Prepend on the way back out: the OUTERMOST layer's post-work runs
    // LAST (it called `next` first, so it unwinds last), so prepending
    // makes left-to-right in the final header match request-time order.
    resp.header("x-order", if prev == "" { tag } else { "${tag},${prev}" })
    resp
}

fn tag_layer(tag str) -> Middleware {
    middleware(fn(req ServerRequest, next Handler) -> ServerResponse => add_tag(tag, next, req))
}
```

`Middleware` itself is a bare newtype over `fn(Handler) -> Handler`
(`Middleware.new(f)` is the low-level "power form" for one-time setup work
that should run once per composition, not once per request — `middleware(...)`
above is what nearly everything should use instead).

## `Router.@use` and ordering

```nova
test "middleware: canon middleware(fn(req, next)) form; first .use() call is outermost" {
    mut r = Router.new()
    r.use(tag_layer("A"))
    r.use(tag_layer("B"))
    r.get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "base"))!!
    ro wire = serve_once(r, get_req("/x"))
    // request order A -> B -> handler; unwinding tags the header A,B
    assert(wire_str(wire).contains("x-order: A,B"))
}
```

**The first `.use()` call is the outermost wrap and runs first** at
request time (`r.use(a); r.use(b)` → request flow is `a → b → handler`)
— this is real `chi` semantics (`chi`'s `chain()` builds `mws[0]` as the
outermost wrap), the same rule Express follows for `app.use(a); app.use(b)`.
Layers accumulate on the router and are baked into each route's handler
**at registration time** (`@route`/`@get`/…/`@nest` all funnel through the
same insertion point) — one closure-wrap per route at setup, not one per
request.

**Only routes registered *after* `.use()` are wrapped** — the same rule
`chi` documents: add your middlewares before the routes they should cover.

## `@then`: composing two middlewares

```nova
test "middleware: @then composes two middlewares into one (same order as two .use() calls)" {
    mut r = Router.new()
    r.use(tag_layer("A").then(tag_layer("B")))
    r.get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "base"))!!
    ro wire = serve_once(r, get_req("/x"))
    assert(wire_str(wire).contains("x-order: A,B"))
}
```

`a.then(b)` composes `a` **outside**, `b` **inside** — `a.then(b).apply(h) == a.apply(b.apply(h))`
— exactly equivalent to `r.use(a); r.use(b)`. Useful for building one
reusable `Middleware` value out of several smaller ones (a "stack" you hand
to several routers) instead of repeating a `.use()` sequence everywhere.

## Router `@use` and `@nest`

`r.nest(prefix, sub)` re-inserts `sub`'s already-registered routes into `r`
via the same registration path `@route` uses — so `r`'s **current** layers
wrap `sub`'s routes too, **outside** whatever layers `sub` itself already
had at its own registration time. Nesting the *same* sub-router into two
different parents does not cross-contaminate — `@nest` never mutates `sub`
(value semantics), so each parent gets its own independently-wrapped copy.

## What gets wrapped

| Registered via | Wrapped by `.use()`? |
|---|---|
| A route's method handlers (`@get`/`@post`/…) | Yes |
| `MethodRouter.@fallback` (per-route 405 override) | Yes — and if a route has no custom fallback but layers exist, the *default* `405 + Allow` is materialized and wrapped too, so e.g. a CORS preflight `OPTIONS` on a GET-only route still sees the middleware |
| `Router.@fallback` (global 404) | **No** — it is not a registered "route" in the trie, so wrap-at-registration has no hook for it; behaves like Axum's `route_layer` rather than a whole-`Service` `.layer()` |

## Writing your own — batteries style

The four batteries in [batteries.md](batteries.md) split into two shapes —
pick by how many scalar knobs your middleware needs:

- **Up to three scalar params → a bare function with default params**
  (sample: `compression`/`ratelimit`). No config type at all: a top-level
  `fn my_thing(a int, b bool = false) -> Middleware` that closes over its
  params and delegates to a top-level `_apply` function (keeping the
  closure's capture set to exactly what it needs, one level of nesting).
- **More than that — lists, a set of independent toggles → a config type +
  a *private* `@middleware()` + a *public*, same-named free function**
  (sample: `cors`/`logger`). The type stays a fluent builder (repeatable
  `@allow_origin(...)`-style methods, several boolean toggles); `@middleware()`
  itself is not `export`ed, so `my_thing(cfg)` is the one public entry point
  — never two ways to reach the same middleware.

## Related documents

**Full example:** [`examples/04-middleware`](../examples/04-middleware) — a custom middleware, `@then`, layer ordering, `log`+`ratelimit`, running for real.

- [routing.md](routing.md) — `Router.@route`/`@nest` themselves
- [batteries.md](batteries.md) — cors/compress/log/ratelimit, all built this way
- [auth.md](auth.md) — `require_jwt`/`session`, two more middlewares
- [`src/middleware.nv`](../src/middleware.nv), [`src/middleware_test.nv`](../src/middleware_test.nv)
