# Auth: Bearer, Basic, JWT, cookies, sessions

**English** | [Русский](auth.ru.md)

Auth building blocks — extractors and middleware, not a framework of their
own: `Bearer`/`BasicAuth` header extractors, `JwtClaims[T]` over `std`'s
HS256 JWT (Polaris wraps it, it does not reimplement any crypto), a
`CookieJar` extractor + `Set-Cookie` helper, and a sessions **skeleton**
(`SessionStore` protocol + an in-memory implementation + `session_layer`
middleware).

Source: [`src/auth.nv`](../src/auth.nv).

---

## Contents

- [Bearer](#bearer)
- [BasicAuth](#basicauth)
- [JWT: `JwtAuth` + `JwtClaims[T]` + `require_jwt`](#jwt-jwtauth--jwtclaimst--require_jwt)
- [Cookies: `CookieJar` + `Set-Cookie`](#cookies-cookiejar--set-cookie)
- [Sessions](#sessions)
- [Related documents](#related-documents)

---

## Bearer

```nova
test "auth: Bearer extractor — token in, 401 out on a missing/wrong-scheme header" {
    mut r = Router.new()
    r.get("/who", fn(req ServerRequest) -> ServerResponse {
        match Bearer.from_request(req) {
            Ok(b)  => ServerResponse.text(StatusCode.OK, "tok=${b.token()}")
            Err(e) => e.into_response()
        }
    })!!
    assert(wire_str(serve_once(r, get_req_h("/who", "Authorization", "Bearer abc"))).contains("tok=abc"))
    assert(status_line(serve_once(r, get_req("/who"))) == "HTTP/1.1 401 Unauthorized")
}
```

`Bearer.from_request` (RFC 6750) reads `Authorization: Bearer <token>`; a
missing header or wrong scheme is a `401`. Pair it with
`unauthorized_bearer()` when you want the `WWW-Authenticate: Bearer`
challenge header on a hand-rolled guard (`require_jwt`, below, already sets
it).

## BasicAuth

```nova
test "auth: BasicAuth extractor decodes user:pass" {
    mut r = Router.new()
    r.get("/basic", fn(req ServerRequest) -> ServerResponse {
        match BasicAuth.from_request(req) {
            Ok(a)  => ServerResponse.text(StatusCode.OK, "u=${a.user()}")
            Err(e) => e.into_response()
        }
    })!!
    ro raw = get_req_h("/basic", "Authorization", "Basic YWxpY2U6czNjcmV0") // base64("alice:s3cret")
    assert(wire_str(serve_once(r, raw)).contains("u=alice"))
}
```

`BasicAuth.from_request` (RFC 7617) decodes `Authorization: Basic base64(user:pass)`,
splitting on the **first** `:` (a user-id must not itself contain one, per
the RFC). Malformed base64, a missing `:`, or a missing/wrong-scheme header
are all `401`.

## JWT: `JwtAuth` + `JwtClaims[T]` + `require_jwt`

```nova
#serde(allow_unknown)
#impl(Deserialize)
type AuthClaims value { ro sub str }

test "auth: require_jwt middleware guard + JwtAuth.claims_at[T] inside the handler" {
    ro secret = "sample-secret".bytes()
    ro auth = JwtAuth.new(secret)
    mut r = Router.new()
    r.layer(require_jwt(auth, fn() -> u64 => 1_500_000_000))
    r.get("/me", fn(req ServerRequest) -> ServerResponse {
        match auth.claims_at[AuthClaims](req, 1_500_000_000) {
            Ok(c)  => ServerResponse.text(StatusCode.OK, "sub=${c.claims().sub}")
            Err(e) => e.into_response()
        }
    })!!
    assert(status_line(serve_once(r, get_req("/me"))) == "HTTP/1.1 401 Unauthorized")
}
```

`JwtAuth.new(secret)` builds an HS256 verifier config. Two ways to use it,
composing rather than fighting each other:

- `require_jwt(auth, now_fn)` — a **middleware** guard: rejects any request
  whose `Authorization: Bearer` token fails signature or `exp`/`nbf`
  validation with `401` + `WWW-Authenticate: Bearer`, passes verified
  requests through untouched.
- `auth.claims_at[T](req, now_ms)` — an in-handler call (turbofish, method-
  level generic) that extracts + verifies + decodes typed claims into `T`.

Both need an explicit clock (`now_fn`/`now_ms`) rather than the `Time`
effect: `Handler` is a plain `fn(ServerRequest) -> ServerResponse` with no
effect row, so a handler body cannot itself perform an effectful call —
production code passes a real clock closure, tests pass a fixed one (as
above), keeping every JWT test fully deterministic.

`T` **must** opt out of serde's strict-by-default field checking with
`#serde(allow_unknown)` — a real JWT payload always carries registered
claims (`exp`/`nbf`/`iat`/`iss`/…) beyond whatever `T` declares, and a
strict `T` would reject every real token with `UnknownField`.

## Cookies: `CookieJar` + `Set-Cookie`

```nova
test "auth: CookieJar + Set-Cookie round-trip" {
    mut r = Router.new()
    r.get("/set", fn(req ServerRequest) -> ServerResponse {
        ro c = "sid=xyz; Path=/; Max-Age=60; Secure; HttpOnly; SameSite=Lax".to_setcookie()!!
        mut resp = ServerResponse.text(StatusCode.OK, "ok")
        resp.set_cookie(c)
        resp
    })!!
    r.get("/jar", fn(req ServerRequest) -> ServerResponse {
        match CookieJar.from_request(req) {
            Ok(jar) => {
                ro sid = jar.get("sid") ?? "?"
                ServerResponse.text(StatusCode.OK, "sid=${sid}")
            }
            Err(e)  => e.into_response()
        }
    })!!
    assert(wire_str(serve_once(r, get_req("/set"))).contains("set-cookie: sid=xyz"))
    assert(wire_str(serve_once(r, get_req_h("/jar", "Cookie", "sid=xyz"))).contains("sid=xyz"))
}
```

`CookieJar.from_request` parses the whole `Cookie:` header once
(axum-extra's `CookieJar` shape) — a missing header is an **empty** jar, not
an error; `@get(name)`/`@all()`/`@len()` read it back. On the way out,
`resp.set_cookie(c)` *appends* a `Set-Cookie` header (multiple cookies per
response are legal and common — this is not `resp.header`, which replaces).

## Sessions

```nova
test "auth: session_layer assigns + persists a session id via cookie" {
    mut store = MemorySessionStore.new(60_000)
    ro cfg = SessionConfig.new().with_cookie_name("sess")
    mut r = Router.new()
    r.layer(session_layer(store, cfg, fn() -> u64 => 1_000, fn() -> str => "gen-1"))
    r.get("/s", fn(req ServerRequest) -> ServerResponse {
        ro sid = req.param("session_id") ?? "?"
        ServerResponse.text(StatusCode.OK, "sid=${sid}")
    })!!

    ro first = serve_once(r, get_req("/s"))
    assert(wire_str(first).contains("sid=gen-1"))
    assert(wire_str(first).contains("set-cookie: sess=gen-1"))
    ro second = serve_once(r, get_req_h("/s", "Cookie", "sess=have-7"))
    assert(wire_str(second).contains("sid=have-7"))
    assert(!wire_str(second).contains("set-cookie"))
}
```

`session_layer(store, cfg, now_fn, id_gen)` guarantees every request reaches
its handler with a `session_id` **path-param-style** value — read it with
`req.param("session_id")`, the same channel `{name}` path segments use. A
request with no session cookie gets a fresh id (from `id_gen`), an eager
empty session save, and a `Set-Cookie` with `SessionConfig`'s secure
defaults (`HttpOnly` + `Secure` + `SameSite=Lax`); a request with an
existing cookie gets its id injected with no new `Set-Cookie`.

`MemorySessionStore` (`HashMap` behind a `Mutex`, fiber-safe) is the
skeleton's one concrete `SessionStore` — save/load/destroy by id, lazy TTL
eviction on `@load`. `SessionData` is flat `str → str` key/value
(`@get(key)`/`mut @set(key, v)`). `SessionStore` itself is a protocol —
implement it against Redis/a database for production; every method takes an
explicit clock for the same reason `JwtAuth` does above.

This is explicitly a **skeleton**, not a finished sessions subsystem — see
[roadmap.md](roadmap.md) for what's next (a generic `[S SessionStore]`
layer, once generic-capture codegen is proven safe for it).

## Related documents

**Full example:** [`examples/05-auth`](../examples/05-auth) — Basic/Bearer/JWT/sessions, a public/private zone split, and a real `/login` token-minting endpoint, running for real (see also [`10-mini-service`](../examples/10-mini-service) for JWT auth in a bigger service).

- [handlers-response.md](handlers-response.md) — `FromRequest`, the protocol every extractor here implements
- [middleware.md](middleware.md) — the `Middleware` core `require_jwt`/`session_layer` build on
- [errors.md](errors.md) — how a `401`/other `HttpError` gets its wire shape
- [`src/auth.nv`](../src/auth.nv), [`src/auth_test.nv`](../src/auth_test.nv)
