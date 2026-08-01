# Batteries: cors, compress, log, ratelimit

**English** | [Русский](batteries.ru.md)

Four ready-made [`Middleware`](middleware.md) implementations, each its own
module, each a fluent config type ending in `@middleware()` (or a
same-named free function — `cors(cfg)`, `compression(cfg)`, `logger(cfg)`,
`ratelimit(cfg)`) you hand to `Router.@use`.

| Battery | Module | Semantics of |
|---|---|---|
| [cors](#cors) | `polaris.middleware.cors` | tower-http `CorsLayer` |
| [compress](#compress) | `polaris.middleware.compress` | tower-http `CompressionLayer` (gzip only) |
| [log](#log) | `polaris.middleware.log` | chi `Logger` + `RequestID` + `RealIP`, folded into one |
| [ratelimit](#ratelimit) | `polaris.middleware.ratelimit` | chi `Throttle` / `tower::limit`, over `std`'s `TokenBucket` |

Source: [`src/middleware/cors.nv`](../src/middleware/cors.nv),
[`compress.nv`](../src/middleware/compress.nv), [`log.nv`](../src/middleware/log.nv),
[`ratelimit.nv`](../src/middleware/ratelimit.nv).

---

## cors

```nova
test "batteries: cors — preflight answered 204, simple request decorated" {
    mut c = Cors.new()
    c.allow_origin("https://app.example")
    mut r = Router.new()
    r.use(cors(c))
    r.get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "ok"))!!

    ro simple = route_once(r, get_req_h("/x", "Origin", "https://app.example"))
    assert(simple.status_code() == 200)
    assert(hdr(simple, "Access-Control-Allow-Origin") == "https://app.example")

    ro preflight_raw = "OPTIONS /x HTTP/1.1\r\nHost: n\r\nOrigin: https://app.example\r\nAccess-Control-Request-Method: GET\r\n\r\n".bytes()
    ro preflight = route_once(r, preflight_raw)
    assert(preflight.status_code() == 204)
}
```

`Cors.new()` starts strict (nothing allowed); `Cors.permissive()` allows any
origin/method/header with no credentials (tower-http's own `permissive()`
shape). Builder methods: `@allow_origin(origin)` (repeatable),
`@allow_any_origin()`, `@allow_method(m)`/`@allow_any_methods()`,
`@allow_header(name)`/`@allow_any_headers()`, `@expose_header(name)`,
`@credentials(bool)`, `@max_age(secs)`.

Preflight `OPTIONS` requests (with `Access-Control-Request-Method`) are
answered **entirely by the middleware** — `204`, `next` is never called, the
wrapped route's own `405` fallback never shows. `Access-Control-Allow-Origin: *`
combined with `credentials(true)` is spec-forbidden and `@middleware()`
**panics** on that config — same as tower-http, on the theory that this
combination is always a caller bug (D325), never live network input.

## compress

```nova
test "batteries: compress — gzip only above min_size and when the client accepts it" {
    mut r = Router.new()
    r.use(compression(Compression.new()))
    consume sb = StringBuilder.new()
    mut i = 0
    while i < 100 { sb.append("the quick brown fox jumps over the lazy dog; "); i += 1 }
    ro big = sb.into_str()
    r.get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, big))!!

    ro accepted = route_once(r, get_req_h("/x", "Accept-Encoding", "gzip"))
    assert(hdr(accepted, "Content-Encoding") == "gzip")
    ro declined = route_once(r, get_req("/x"))
    assert(hdr(declined, "Content-Encoding") == "")
}
```

`Compression.new()` defaults to a 1024-byte minimum size and the default
gzip level (`@min_size(n)`/`@level(l)` to tune). Skipped automatically —
never a bug to layer it everywhere — when: the response is already
streaming (a chunk producer wins the wire), the body is under `min_size`,
the response already carries `Content-Encoding`, the content-type isn't on
the compressible allowlist (`text/*` + json/xml/javascript-ish subtypes), or
the client's `Accept-Encoding` doesn't admit gzip. `Vary: accept-encoding`
is appended whenever the response *would* be negotiable, even when this
particular answer stays identity, so a shared cache never serves a gzip
body to a client that can't decode it. Brotli is not offered — the
underlying `compress` package ships a decoder only, no encoder, so `br`
negotiation is deliberately absent until one exists.

## log

```nova
test "batteries: log — one line per request, X-Request-Id propagated" {
    mut lines []str = []
    ro cfg = AccessLog.new()
    with Time = th.fixed_ms(0), Log = capture_log(lines) {
        mut r = Router.new()
        r.use(logger(cfg))
        r.get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "ok"))!!
        ro resp = route_once(r, get_req("/x"))
        assert(hdr(resp, "x-request-id") == "req-1")
        assert(lines.len() == 1)
        assert(lines[0] == "[req-1] GET /x -> 200 2B in 0ms")
    }
}
```

One line per request: method, path, status, response body size, wall
duration. `AccessLog.new()` defaults to request-id **on**, real-ip **off**;
lines go through the ambient [`Log` effect](serving.md#the-log-effect) — stdout
by default, redirectable in tests via `with Log = capture_log(lines) { ... }`
(the test above captures into a `Vec[str]` — no stdout scraping needed in
your own tests either). `X-Request-Id` is taken from an incoming header
when present and safe, else generated from a per-config counter
(`req-1`, `req-2`, …) and echoed back on the response.
`@real_ip(true)` adds the first `X-Forwarded-For` hop to the line — **off**
by default, chi's own `RealIP` caveat: that header is client-controlled,
only trust it behind a proxy that overwrites it.

`@middleware()` carries a `Time` effect row (it measures wall-clock
duration around the wrapped handler) — tests fix the clock with
`with Time = th.fixed_ms(...)` (`std.testing.handlers`) for deterministic
output, exactly as above. `Log` is NOT in that row: the per-request line is
emitted through a raw `Log.info(...)` op (not checked under
`--strict-effects`, see [serving.md](serving.md#the-log-effect)), so it composes
into the same `with Time = ..., Log = ... { ... }` block freely.

## ratelimit

```nova
test "batteries: ratelimit — burst within capacity passes, then 429 + Retry-After" {
    with Time = th.fixed_ms(0) {
        mut r = Router.new()
        r.use(ratelimit(RateLimit.new(1, 1.0)))
        r.get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "ok"))!!
        assert(route_once(r, get_req("/x")).status_code() == 200)
        ro second = route_once(r, get_req("/x"))
        assert(second.status_code() == 429)
        assert(hdr(second, "retry-after") == "1")
    }
}
```

`RateLimit.new(capacity, per_sec)` — `capacity` tokens of burst, refilled at
`per_sec` tokens/second, wrapping `std`'s `TokenBucket`. Default is **one
global bucket** (chi's `Throttle` shape); `@per_client(true)` keys separate
buckets by the first `X-Forwarded-For` hop (same trust caveat as `log`'s
`RealIP`). A rejected request gets `429` + `Retry-After: <ceil(1/per_sec)>`
seconds — the earliest moment a token can exist again. Like `log`, building
the middleware carries a `Time` effect row (the bucket refills against
`Monotonic.now()`); tests fix the clock the same way.

> **Known simplification**: the bucket is not lock-protected — under true
> M:N parallelism two fibers can in principle both witness the last token.
> An over-admission of roughly one token under contention throttles, it
> does not corrupt state.

## Related documents

**Full example:** [`examples/04-middleware`](../examples/04-middleware) — `log`+`ratelimit` running for real (see also [`10-mini-service`](../examples/10-mini-service) for `log` in a bigger service).

- [middleware.md](middleware.md) — the `Middleware`/`Router.@use` core these build on
- [auth.md](auth.md) — `require_jwt`/`session`, two more ready-made middlewares
- [`src/middleware/`](../src/middleware) — full source + pin tests for all four
