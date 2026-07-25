# 05 — auth

Basic + Bearer/JWT extractors, a `require_jwt`-guarded private zone split
from a public one via `nest` + `.layer()`, a `/login` endpoint that mints a
real HS256 token (`std.crypto.jwt.Jwt.encode_hs256` — Polaris itself only
*verifies* JWTs, it has no login flow of its own), and a session cookie via
`session_layer`.

By way of: axum's `jwt` example, the FastAPI OAuth2/security tutorial.

## Run

```sh
nova build --strict-effects src/main.nv
./main   # binds 0.0.0.0:18086
```

```sh
curl http://localhost:18086/public                                   # public
curl -u alice:s3cret http://localhost:18086/basic                    # welcome, alice
curl -H 'Authorization: Bearer abc123' http://localhost:18086/bearer # token=abc123

curl -o /dev/null -w '%{http_code}\n' http://localhost:18086/private/me   # 401, no token

TOKEN=$(curl -s http://localhost:18086/login/nova-user)
curl -H "Authorization: Bearer $TOKEN" http://localhost:18086/private/me  # sub=nova-user

curl -c /tmp/jar -s http://localhost:18086/session/whoami   # session=sess-4000000000, Set-Cookie
curl -b /tmp/jar -s http://localhost:18086/session/whoami   # same id, no new Set-Cookie
```

## What to poke at

- Swap `demo_now()`'s fixed clock for a real one and watch tokens minted
  before the process started still verify (until `exp`) — see the note in
  `main.nv` on why the clock is a plain closure, not the `Time` effect.
- Add a second claim (`role`) to `mint_token`/`AuthClaims` and branch on it
  inside `/private/me`.
- Layer `require_jwt` at the TOP level instead of nesting `/private` — see
  what happens to `/public` (hint: `.layer()` only wraps routes registered
  *after* the call — [`docs/middleware.md`](../../docs/middleware.md)).

## Related documentation

- [`docs/auth.md`](../../docs/auth.md) — `Bearer`/`BasicAuth`/`JwtAuth`/`CookieJar`/sessions, in full
- [`docs/middleware.md`](../../docs/middleware.md) — `nest` + `.layer()` interaction

[Русский](README.ru.md) · see [`examples/README.md`](../README.md) for why `main()`/`production_main()` come in a pair.
