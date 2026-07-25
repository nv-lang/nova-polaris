# 10 — mini-service

Everything in this example set, combined: a trimmed **RealWorld (Conduit)**
profile — users/auth (register, login, JWT) + articles CRUD + pagination —
plus the `log` middleware and an embedded static landing page. Compact
compared to a flagship example, but the same shape: a real referenceable
starting point for a small service.

By way of: [RealWorld](https://github.com/gothinkster/realworld) (Conduit)
— the "Medium clone API" spec used across dozens of framework
implementations as a maturity benchmark.

## Run

```sh
nova build --strict-effects src/main.nv
./main   # binds 0.0.0.0:18091
```

```sh
curl http://localhost:18091/health              # ok
curl http://localhost:18091/                    # embedded landing page

TOKEN=$(curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"username":"nova","password":"x"}' http://localhost:18091/users)
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"username":"nova","password":"x"}' http://localhost:18091/users/login   # same token back

curl http://localhost:18091/articles             # []

curl -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' \
  -d '{"title":"Hello World","body":"first post"}' http://localhost:18091/articles   # 401, no Bearer

curl -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"title":"Hello World","body":"first post"}' http://localhost:18091/articles
# {"slug":"hello-world","title":"Hello World","body":"first post","author":"demo"}

curl http://localhost:18091/articles                 # the article, listed
curl http://localhost:18091/articles/hello-world      # the article, by slug
curl 'http://localhost:18091/articles?limit=1&offset=0'   # pagination
```

## What's a deliberate simplification here

This is a **demo profile**, not RealWorld's full spec: `users` stores
usernames only (no password hashing/verification — any password "works"
once the username is registered, same simplification 05-auth's `/login`
makes), articles have no `favorited`/`tagList`/comments, and `author` is
always `"demo"` rather than the real caller's JWT `sub` (left as a "what to
poke at" — see below). A full RealWorld port is explicitly a **separate,
after-release** candidate, not this example's job.

## What to poke at

- Read `sub` out of the caller's own JWT (`auth.claims_at[...]`, see
  [`05-auth`](../05-auth/)) and use it as `Article.author` instead of the
  hardcoded `"demo"`.
- Add `PUT`/`DELETE /articles/{slug}` (same `MethodRouter`-chain shape
  `/articles` already uses for GET+POST — see
  [`03-json-api`](../03-json-api/) for why that matters here).
- Add a real password check (even a trivial one) to `/users/login`.

## Related documentation

- [`docs/handlers-response.md`](../../docs/handlers-response.md), [`docs/auth.md`](../../docs/auth.md), [`docs/middleware.md`](../../docs/middleware.md), [`docs/static-files.md`](../../docs/static-files.md), [`docs/serving.md`](../../docs/serving.md) — every piece this example composes

[Русский](README.ru.md) · see [`examples/README.md`](../README.md) for why `main()`/`production_main()` come in a pair.
