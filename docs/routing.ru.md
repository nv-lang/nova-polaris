# Роутинг

[English](routing.md) | **Русский**

`Router` — сегмент-trie (Axum-класса): литеральные сегменты, `{name}`-параметры
и `{*rest}`-catch-all, сопоставляемые по структурному приоритету — **не** по
порядку регистрации. Сама регистрация — fallible: конфликтующий route — это
типизированный `Result`, никогда не паника.

Дизайн: [Plan 222.1](https://github.com/nv-lang/nova/blob/main/docs/plans/222.1-router-from-scratch.md)
(репа nova). Исходник: [`src/server_router.nv`](../src/server_router.nv).

---

## Содержание

- [Регистрация route](#регистрация-route)
- [Две формы регистрации: statement и chain](#две-формы-регистрации-statement-и-chain)
- [Шаблоны путей](#шаблоны-путей)
- [`MethodRouter`: композиция методов на одном пути](#methodrouter-композиция-методов-на-одном-пути)
- [`nest`: суб-роутеры с префиксом](#nest-суб-роутеры-с-префиксом)
- [Fallback'и: глобальный 404 vs per-route 405](#fallbackи-глобальный-404-vs-per-route-405)
- [Конфликты routes — типизированные ошибки](#конфликты-routes--типизированные-ошибки)
- [Связанные документы](#связанные-документы)

---

## Регистрация route

```nova
test "routing: statement-form registration with !!" {
    mut r = Router.new()
    r.get("/health", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "ok"))!!
    ro wire = serve_once(r, get_req("/health"))
    assert(status_line(wire) == "HTTP/1.1 200 OK")
}
```

`Router.mut @get/@post/@put/@delete/@patch(path, handler)` каждый возвращает
`Result[Router, HttpError]` — **не** `Result[(), HttpError]`. Payload у `Ok`
— сам роутер (`Ok(@)`), это и делает возможными обе формы регистрации ниже
на одной и той же сигнатуре.

Голая `fn`/замыкание в позиции, ожидающей `Handler`, автоподнимается в
`Handler` (`type Handler fn(ServerRequest) -> ServerResponse` — newtype над
fn-типом, не алиас): `r.get(path, fn(req ServerRequest) -> ServerResponse { ... })`
не требует оборачивающего вызова. Значение `Handler` вызывается напрямую
(`h(req)`) — см. [handlers-response.md](handlers-response.ru.md#handler).

## Две формы регистрации: statement и chain

Поскольку payload у `Ok` — сам роутер, регистрация компонуется двумя
способами:

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

- **Statement-форма** — `r.get(..)!!` отдельной строкой, один вызов на
  строку. Большинство кода в этом наборе доков использует именно её; читается
  ближе всего к Express/chi.
- **`?`-chain** — внутри функции, которая сама возвращает
  `Result[Router, HttpError]`, регистрации цепляются через `?`, и первая же
  ошибка коротко замыкает всю функцию.
- **Fluent `!!`-chain на rvalue** — `Router.new().get(..)!!.post(..)!!` —
  удобно для определения роутера одним выражением (таблица-константа в
  начале модуля).

Обе формы вызывают ровно одну и ту же машинерию `@route`/`@insert_segs` —
выбирайте ту, что лучше читается в конкретном месте.

## Шаблоны путей

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

- `{name}` совпадает ровно с одним сегментом пути; его декодированное
  значение читается через `req.param("name")` (см.
  [handlers-response.md](handlers-response.ru.md)).
- `{*name}` — catch-all — обязан быть **последним** сегментом шаблона
  (`{*rest}` где-либо ещё — ошибка `Err` на этапе регистрации), а его
  значение — склеенный обратно, percent-декодированный остаток пути.
- **Приоритет структурный**: литеральные сегменты выигрывают у `{name}`,
  который выигрывает у `{*name}`, с backtracking'ом на тупике глубже по
  дереву — независимо от порядка регистрации routes. Так же ведёт себя Axum
  (и `net/http` из Go 1.22), в отличие от линейного роутера first-match.

## `MethodRouter`: композиция методов на одном пути

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

`get(h)`/`post(h)`/`put(h)`/`delete(h)`/`patch(h)` — свободные функции,
начинающие цепочку `MethodRouter` (форма Axum'а `get(handler).post(handler2)`);
`Router.@route(path, mr)` регистрирует весь набор атомарно на одном пути.
Пять методов `Router.@get`/`@post`/`@put`/`@delete`/`@patch(path, h)`,
используемые в остальной части набора доков — сахар над
`@route(path, get(h))` и т.п. — обе формы дают одну и ту же запись в дереве.

Когда путь совпал, а зарегистрированного метода нет, Polaris отвечает
общим `405 Method Not Allowed` с заголовком `Allow: <methods>`, собранным из
того, что реально зарегистрировано на этом route — никакого дополнительного
кода не нужно.

## `nest`: суб-роутеры с префиксом

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

`r.nest(prefix, sub)` перерегистрирует каждый уже конфликт-свободный route из
`sub` в `r`, под `prefix` — конфликт префикса с уже существующим route в `r`
— как всегда, типизированный `Err`, не паника. Собственный `@fallback` у
`sub` (его 404 роутера) **не** переносится — участвуют только верхнеуровневый
`Router.@fallback` и per-route `MethodRouter.@fallback`; про то, как `nest`
взаимодействует с `.layer()`, — в
[middleware.md](middleware.ru.md#router-layer-и-nest).

## Fallback'и: глобальный 404 vs per-route 405

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

Два разных хука, легко перепутать по имени:

| Хук | Срабатывает когда | Область |
|---|---|---|
| `Router.mut @fallback(h)` | **ни один** путь в дереве не совпал вообще | глобально — 404 всего роутера |
| `MethodRouter.mut @fallback(h)` | путь совпал, а метод — нет | 405 конкретного route'а |

Ни один не задан по умолчанию: незаданный `Router.@fallback` отдаёт простой
`404 page not found`; незаданный `MethodRouter.@fallback` отдаёт общий
`405 + Allow`, показанный выше.

## Конфликты routes — типизированные ошибки

```nova
test "routing: a duplicate/conflicting route registration is a typed Err, not a panic" {
    mut r = Router.new()
    r.get("/dup", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "first"))!!
    ro second = r.route("/dup", get(fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "second")))
    assert(match second { Err(_) => true, Ok(_) => false })
}
```

Axum на эквивалентном конфликте паникует в момент построения роутера;
Polaris вместо этого возвращает типизированный `Err(HttpError)` — сознательное
улучшение, заложенное в дизайн. Ловятся три формы конфликта: точный дубль
пути, два разных имени `{name}`-параметра, претендующих на один и тот же
слот дерева, и `{*rest}`, не являющийся последним сегментом шаблона.

## Связанные документы

**Полный пример:** [`examples/02-routing`](../examples/02-routing) — каждый приём этой страницы, реально запущенный.

- [handlers-response.md](handlers-response.ru.md) — `ServerRequest`/`ServerResponse`, чтение параметров, `Handler`
- [middleware.md](middleware.ru.md) — `Router.@layer` и его взаимодействие с `@nest`
- [errors.md](errors.ru.md) — `HttpError` и то, как он превращается в ответ на проводе
- [`src/server_router.nv`](../src/server_router.nv) — реализация дерева
- [`src/router_test.nv`](../src/router_test.nv) — полный набор pin-тестов, из которого взяты примеры этой страницы
