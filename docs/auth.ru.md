# Auth: Bearer, Basic, JWT, куки, сессии

[English](auth.md) | **Русский**

Строительные блоки auth — extractors и middleware, не собственный фреймворк:
extractors заголовков `Bearer`/`BasicAuth`, `JwtClaims[T]` поверх HS256 JWT
из `std` (Polaris оборачивает его, не переизобретает никакую криптографию),
extractor `CookieJar` + хелпер `Set-Cookie`, и **скелет** сессий (протокол
`SessionStore` + in-memory реализация + middleware `session_layer`).

Исходник: [`src/auth.nv`](../src/auth.nv).

---

## Содержание

- [Bearer](#bearer)
- [BasicAuth](#basicauth)
- [JWT: `JwtAuth` + `JwtClaims[T]` + `require_jwt`](#jwt-jwtauth--jwtclaimst--require_jwt)
- [Куки: `CookieJar` + `Set-Cookie`](#куки-cookiejar--set-cookie)
- [Сессии](#сессии)
- [Связанные документы](#связанные-документы)

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

`Bearer.from_request` (RFC 6750) читает `Authorization: Bearer <token>`;
отсутствующий заголовок или неверная схема — `401`. Скомбинируйте с
`unauthorized_bearer()`, когда нужен challenge-заголовок
`WWW-Authenticate: Bearer` на самописной проверке (`require_jwt` ниже уже
его ставит).

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

`BasicAuth.from_request` (RFC 7617) декодирует
`Authorization: Basic base64(user:pass)`, разбивая по **первому** `:`
(user-id по спеке сам не может его содержать). Битый base64, отсутствующий
`:`, отсутствующий или неверный заголовок — всё это `401`.

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

`JwtAuth.new(secret)` строит HS256-верификатор. Два способа применения,
которые компонуются, а не мешают друг другу:

- `require_jwt(auth, now_fn)` — middleware-проверка: отклоняет любой запрос,
  чей `Authorization: Bearer` не прошёл проверку подписи или `exp`/`nbf`, с
  `401` + `WWW-Authenticate: Bearer`; проверенные запросы пропускает без
  изменений.
- `auth.claims_at[T](req, now_ms)` — вызов внутри хендлера (turbofish,
  метод-уровневый generic), извлекающий + проверяющий + декодирующий
  типизированные claims в `T`.

Обоим нужны явные часы (`now_fn`/`now_ms`), а не эффект `Time`: `Handler` —
это обычная `fn(ServerRequest) -> ServerResponse` без эффект-ряда, поэтому
тело хендлера само не может вызвать эффектную функцию — production-код
передаёт замыкание-часы на реальном времени, тесты — фиксированное (как
выше), что делает каждый JWT-тест полностью детерминированным.

`T` **обязан** отключить строгую по умолчанию проверку полей serde через
`#serde(allow_unknown)` — реальный payload JWT всегда несёт
зарегистрированные claims (`exp`/`nbf`/`iat`/`iss`/…) сверх того, что
объявляет `T`, и строгий `T` отклонил бы любой реальный токен с
`UnknownField`.

## Куки: `CookieJar` + `Set-Cookie`

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

`CookieJar.from_request` парсит весь заголовок `Cookie:` один раз (форма
`CookieJar` из axum-extra) — отсутствующий заголовок даёт **пустую** jar,
не ошибку; `@get(name)`/`@all()`/`@len()` читают её обратно. На выходе
`resp.set_cookie(c)` **добавляет** заголовок `Set-Cookie` (несколько кук в
одном ответе — легально и обычно; это не `resp.header`, который заменяет).

## Сессии

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

`session_layer(store, cfg, now_fn, id_gen)` гарантирует, что каждый запрос
доходит до хендлера со значением `session_id`, доступным **по каналу
path-параметров** — читайте через `req.param("session_id")`, тем же
каналом, что используют `{name}`-сегменты пути. Запрос без cookie сессии
получает свежий id (от `id_gen`), eager-сохранение пустой сессии и
`Set-Cookie` с безопасными дефолтами `SessionConfig` (`HttpOnly` +
`Secure` + `SameSite=Lax`); запрос с существующей cookie получает свой id
без нового `Set-Cookie`.

`MemorySessionStore` (`HashMap` под `Mutex`, fiber-safe) — единственная
конкретная реализация `SessionStore` в скелете: save/load/destroy по id,
lazy TTL-вытеснение при `@load`. `SessionData` — плоский `str → str`
key/value (`@get(key)`/`mut @set(key, v)`). Сам `SessionStore` — протокол —
реализуйте его поверх Redis/базы данных для production; каждый метод
принимает явные часы по той же причине, что и `JwtAuth` выше.

Это осознанно **скелет**, не законченная подсистема сессий — что дальше —
см. [roadmap.md](roadmap.ru.md) (обобщённый слой
`[S SessionStore]`, отложенный до подтверждения безопасности
generic-захвата в кодогене для этой формы).

## Связанные документы

**Полный пример:** [`examples/05-auth`](../examples/05-auth) — Basic/Bearer/JWT/сессии, разделение публичной/приватной зоны и настоящий `/login`, чеканящий токен, реально запущенные (см. также [`10-mini-service`](../examples/10-mini-service) — JWT-авторизация в сервисе побольше).

- [handlers-response.md](handlers-response.ru.md) — `FromRequest`, протокол, который реализует каждый extractor здесь
- [middleware.md](middleware.ru.md) — ядро `Middleware`, на котором построены `require_jwt`/`session_layer`
- [errors.md](errors.ru.md) — как `401`/другая `HttpError` получает форму на проводе
- [`src/auth.nv`](../src/auth.nv), [`src/auth_test.nv`](../src/auth_test.nv)
