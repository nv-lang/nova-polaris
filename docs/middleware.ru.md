# Middleware

[English](middleware.md) | **Русский**

`Middleware` оборачивает `Handler` в новый `Handler` — Go/[chi](https://github.com/go-chi/chi)'шный
`func(http.Handler) http.Handler`, один в один. Обобщённый `Service` из
Tower (poll_ready/backpressure) сознательно **не** портирован: у
fiber-модели Nova нет async-сигнала готовности как класса, а backpressure
уже живёт на уровне accept-loop (`ServerPolicy.max_inflight` — см.
[serving.md](serving.ru.md)).

Исходник: [`src/middleware.nv`](../src/middleware.nv).

---

## Содержание

- [Канон-форма: `middleware(fn(req, next))`](#канон-форма-middlewarefnreq-next)
- [`Router.@layer` и порядок](#routerlayer-и-порядок)
- [`@then`: композиция двух middleware](#then-композиция-двух-middleware)
- [Router `@layer` и `@nest`](#router-layer-и-nest)
- [Что оборачивается](#что-оборачивается)
- [Пишем свой — в стиле батареек](#пишем-свой--в-стиле-батареек)
- [Связанные документы](#связанные-документы)

---

## Канон-форма: `middleware(fn(req, next))`

```nova
export fn middleware(f fn(ServerRequest, Handler) -> ServerResponse) -> Middleware
```

Строим middleware из **одного плоского замыкания** — без вложенной
церемонии `fn(next) -> Handler`. `next` — обычное значение `Handler`:
вызываем напрямую (`next(req)`), выполняем код до/после него, либо
коротко замыкаем, вернув свой ответ без вызова вовсе.

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
    ro t = tag
    middleware(fn(req ServerRequest, next Handler) -> ServerResponse => add_tag(t, next, req))
}
```

Сам `Middleware` — голый newtype над `fn(Handler) -> Handler`
(`Middleware.new(f)` — низкоуровневая «силовая» форма для одноразовой
настройки, которая должна выполняться один раз за композицию, а не один раз
на запрос — вместо неё почти всегда стоит использовать `middleware(...)`
выше).

## `Router.@layer` и порядок

```nova
test "middleware: canon middleware(fn(req, next)) form; first .layer() call is outermost" {
    mut r = Router.new()
    r.layer(tag_layer("A"))
    r.layer(tag_layer("B"))
    r.get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "base"))!!
    ro wire = serve_once(r, get_req("/x"))
    // request order A -> B -> handler; unwinding tags the header A,B
    assert(wire_str(wire).contains("x-order: A,B"))
}
```

**Первый вызов `.layer()` — самый внешний слой, и он же выполняется
первым** во время запроса (`r.layer(a); r.layer(b)` → поток запроса
`a → b → handler`) — это настоящая семантика `chi` (`chi`'шный `chain()`
строит `mws[0]` самым внешним слоем), то же правило, которому следует
Express для `app.use(a); app.use(b)`. Слои накапливаются на роутере и
запекаются в хендлер каждого route'а **в момент регистрации** (`@route`/
`@get`/…/`@nest` — все сходятся в одной точке вставки) — одна обёртка
замыканием на route при setup'е, а не одна на запрос.

**Оборачиваются только routes, зарегистрированные *после* `.layer()`** —
то же правило, что документирует `chi`: добавляйте middleware до routes,
которые они должны покрывать.

## `@then`: композиция двух middleware

```nova
test "middleware: @then composes two middlewares into one (same order as two .layer() calls)" {
    mut r = Router.new()
    r.layer(tag_layer("A").then(tag_layer("B")))
    r.get("/x", fn(req ServerRequest) -> ServerResponse => ServerResponse.text(StatusCode.OK, "base"))!!
    ro wire = serve_once(r, get_req("/x"))
    assert(wire_str(wire).contains("x-order: A,B"))
}
```

`a.then(b)` компонует `a` **снаружи**, `b` **внутри** —
`a.then(b).apply(h) == a.apply(b.apply(h))` — ровно эквивалентно
`r.layer(a); r.layer(b)`. Полезно, чтобы собрать одно переиспользуемое
значение `Middleware` из нескольких меньших (общий «стек», который вы
передаёте нескольким роутерам), вместо повторения последовательности
`.layer()` в каждом месте.

## Router `@layer` и `@nest`

`r.nest(prefix, sub)` перевставляет уже зарегистрированные routes из `sub`
в `r` через тот же путь регистрации, что использует `@route` — так что
**текущие** слои `r` оборачивают и routes из `sub`, **снаружи** тех слоёв,
что уже были у `sub` в момент его собственной регистрации. Вложение одного
и того же суб-роутера в двух разных родителей не приводит к
перекрёстному загрязнению — `@nest` никогда не мутирует `sub` (value-
семантика), так что каждый родитель получает свою независимо обёрнутую
копию.

## Что оборачивается

| Зарегистрировано через | Оборачивается `.layer()`? |
|---|---|
| Хендлеры методов route'а (`@get`/`@post`/…) | Да |
| `MethodRouter.@fallback` (per-route переопределение 405) | Да — и если у route нет собственного fallback, но слои есть, *дефолтный* `405 + Allow` материализуется и тоже оборачивается, так что, например, CORS-preflight `OPTIONS` на GET-only route всё равно видит middleware |
| `Router.@fallback` (глобальный 404) | **Нет** — это не зарегистрированный «route» в дереве, поэтому у wrap-at-registration нет для него точки входа; ведёт себя как `route_layer` из Axum, а не как `.layer()` на весь `Service` |

## Пишем свой — в стиле батареек

Каждая батарейка из [batteries.md](batteries.ru.md) — это fluent-конфиг,
заканчивающийся билдером `@middleware()`, который оборачивает канон-форму
`middleware(...)` — это и есть рекомендуемая форма для вашего собственного
middleware: небольшой конфиг-значение, метод-билдер и верхнеуровневая
`_apply`-функция, на которую делегирует замыкание (держим набор захвата
каждого замыкания ровно тем, что нужно, один уровень вложенности).

## Связанные документы

- [routing.md](routing.ru.md) — сами `Router.@route`/`@nest`
- [batteries.md](batteries.ru.md) — cors/compress/log/ratelimit, все построены так же
- [auth.md](auth.ru.md) — `require_jwt`/`session_layer`, ещё два middleware
- [`src/middleware.nv`](../src/middleware.nv), [`src/middleware_test.nv`](../src/middleware_test.nv)
