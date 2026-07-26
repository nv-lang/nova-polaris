# Auth: Bearer, Basic, JWT, cookies, sessions

**English** | [Русский](auth.ru.md)

Auth building blocks — extractors and middleware, not a framework of their
own: `Bearer`/`BasicAuth` header extractors, `JwtClaims[T]` over `std`'s
HS256 JWT (Polaris wraps it, it does not reimplement any crypto), a
`CookieJar` extractor + `Set-Cookie` helper, and a sessions **skeleton**
(`SessionStore` effect + an in-memory handler + `session_layer` middleware).

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
    with Time = th.fixed_ms(1_500_000_000) {
        ro secret = "sample-secret".bytes()
        ro auth = JwtAuth.new(secret)
        mut r = Router.new()
        r.layer(require_jwt(auth))
        r.get("/me", fn(req ServerRequest) -> ServerResponse {
            match auth.claims_at[AuthClaims](req, 1_500_000_000) {
                Ok(c)  => ServerResponse.text(StatusCode.OK, "sub=${c.claims().sub}")
                Err(e) => e.into_response()
            }
        })!!
        assert(status_line(serve_once(r, get_req("/me"))) == "HTTP/1.1 401 Unauthorized")
    }
}
```

`JwtAuth.new(secret)` builds an HS256 verifier config. Two ways to use it,
composing rather than fighting each other:

- `require_jwt(auth) Time -> Middleware` — a **middleware** guard: rejects
  any request whose `Authorization: Bearer` token fails signature or
  `exp`/`nbf` validation with `401` + `WWW-Authenticate: Bearer`, passes
  verified requests through untouched. The clock comes from the `Time`
  effect — production sees the real clock (ambient default handler), tests
  wrap with `with Time = th.fixed_ms(now_ms) { ... }` (as above).
- `auth.claims_at[T](req, now_ms)` — an in-handler call (turbofish, method-
  level generic) that extracts + verifies + decodes typed claims into `T`.
  This one still takes an **explicit** `now_ms`, not `Time`: it runs inside a
  real `Handler` body (`fn(ServerRequest) -> ServerResponse`, no effect row),
  so it cannot itself perform an effectful call — the same reasoning
  `require_jwt` used to follow before it moved to `Time` (Plan 222.20 Ф.3
  Волна B).

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
    with Time = th.fixed_ms(1_000), Random = th.seeded(7), SessionStore = memory_session_store(60_000) {
        ro cfg = SessionConfig.new().with_cookie_name("sess")
        mut r = Router.new()
        r.layer(session_layer(cfg))
        r.get("/s", fn(req ServerRequest) -> ServerResponse {
            ro sid = req.param("session_id") ?? "?"
            ServerResponse.text(StatusCode.OK, "sid=${sid}")
        })!!

        ro first = serve_once(r, get_req("/s"))
        assert(wire_str(first).contains("set-cookie: sess="))
        ro second = serve_once(r, get_req_h("/s", "Cookie", "sess=have-7"))
        assert(wire_str(second).contains("sid=have-7"))
        assert(!wire_str(second).contains("set-cookie"))
    }
}
```

`session_layer(cfg) Random -> Middleware` guarantees every request reaches
its handler with a `session_id` **path-param-style** value — read it with
`req.param("session_id")`, the same channel `{name}` path segments use. A
request with no session cookie gets a fresh id (16 random bytes,
hex-encoded via the `Random` effect), an eager empty session save, and a
`Set-Cookie` with `SessionConfig`'s secure defaults (`HttpOnly` + `Secure` +
`SameSite=Lax`); a request with an existing cookie gets its id injected with
no new `Set-Cookie`.

`SessionStore` is an **effect** (Plan 222.20 Ф.3 Волна B), not a protocol —
the textbook resource-substitution case: production plugs in Redis/a
database, tests plug in an in-memory (or hand-rolled) double, both via
`with SessionStore = ... { ... }` around dispatch. `memory_session_store(
ttl_ms)` is the skeleton's one built-in handler factory — `HashMap` behind a
`Mutex` (fiber-safe), lazy TTL eviction on `load`, its own clock read from
the `Time` effect internally (no `now_ms` anywhere in the `SessionStore`
surface any more). Unlike `Time`/`Log`, `SessionStore` has **no ambient
default handler** — it is a resource a production caller must explicitly
choose, exactly like `mock_http()`/`real_http()`, not an always-safe
stdout-style default. `SessionData` is flat `str → str` key/value
(`@get(key)`/`mut @set(key, v)`), unchanged.

This is explicitly a **skeleton**, not a finished sessions subsystem — see
[roadmap.md](roadmap.md) for what's next (a generic multi-backend layer,
once generic-capture codegen is proven safe for it).

## Related documents

**Full example:** [`examples/05-auth`](../examples/05-auth) — Basic/Bearer/JWT/sessions, a public/private zone split, and a real `/login` token-minting endpoint, running for real (see also [`10-mini-service`](../examples/10-mini-service) for JWT auth in a bigger service).

- [handlers-response.md](handlers-response.md) — `FromRequest`, the protocol every extractor here implements
- [middleware.md](middleware.md) — the `Middleware` core `require_jwt`/`session_layer` build on
- [errors.md](errors.md) — how a `401`/other `HttpError` gets its wire shape
- [`src/auth.nv`](../src/auth.nv), [`src/auth_test.nv`](../src/auth_test.nv)
