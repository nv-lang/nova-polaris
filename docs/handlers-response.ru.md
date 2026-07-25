# Хендлеры, запросы и ответы

[English](handlers-response.md) | **Русский**

Эта страница покрывает модель запрос/ответ, с которой работает хендлер:
сам `Handler`, чтение `ServerRequest`, построение `ServerResponse`, протокол
схождения `IntoResponse`, позволяющий хендлеру возвращать не только голый
`ServerResponse`, типизированное извлечение через `FromRequest`, и
`StatusCode`.

Исходник: [`src/server.nv`](../src/server.nv) (`ServerRequest`/`ServerResponse`/`Handler`),
[`src/response.nv`](../src/response.nv) (`IntoResponse`/`Json[T]`),
[`src/extract.nv`](../src/extract.nv) (`FromRequest` + extractors),
[`src/multipart.nv`](../src/multipart.nv).

---

## Содержание

- [`Handler`](#handler)
- [`ServerRequest`](#serverrequest)
- [Конструкторы `ServerResponse`](#конструкторы-serverresponse)
- [`IntoResponse`](#intoresponse)
- [Типизированное извлечение: `FromRequest`](#типизированное-извлечение-fromrequest)
- [`Bytes`/`Text`/`Headers`](#bytestextheaders)
- [`multipart/form-data`](#multipartform-data)
- [`StatusCode`](#statuscode)
- [Связанные документы](#связанные-документы)

---

## `Handler`

```nova
export type Handler fn(ServerRequest) -> ServerResponse
```

`Handler` — newtype над fn-типом, **не** алиас (D52/D55): голая функция или
замыкание автоматически поднимается в него везде, где он ожидается — каждый
вызов `Router.@get`/`@post`/… в этом наборе доков передаёт замыкание
напрямую, без `Handler.new(...)`/оборачивающего вызова. Значение `Handler`
вызывается напрямую (`h(req)`) — единственная осмысленная операция над
обёрнутой функцией, та же форма, что у Go'шного `http.HandlerFunc`.

## `ServerRequest`

```nova
test "handlers-response: ServerRequest accessors — param/query_param/header/body_bytes" {
    mut r = Router.new()
    r.post("/echo/{tag}", fn(req ServerRequest) -> ServerResponse {
        ro tag = req.param("tag") ?? "?"
        ro q = req.query_param("q") ?? "?"
        ro ua = req.header("user-agent") ?? "?"
        ro body = unsafe { req.body_bytes().to_str_unchecked() }
        ServerResponse.text(StatusCode.OK, "tag=${tag} q=${q} ua=${ua} body=${body}")
    })!!
    ro raw = "POST /echo/x?q=hi HTTP/1.1\r\nHost: n\r\nUser-Agent: t\r\nContent-Length: 3\r\n\r\nabc".bytes()
    ro wire = serve_once(r, raw)
    assert(wire_str(wire).contains("tag=x q=hi ua=t body=abc"))
}
```

| Метод | Сигнатура | Заметки |
|---|---|---|
| `@method` | `() -> Method` | метод запроса |
| `@path` | `() -> str` | декодированный путь, без query |
| `@target` | `() -> str` | сырой request-target (`path[?query]`) |
| `@headers` | `() -> HeaderMap` | полная карта заголовков |
| `@header` | `(name str) -> Option[str]` | первое значение, регистронезависимо |
| `@param` | `(name str) -> Option[str]` | совпавший `{name}`-сегмент пути |
| `@query_param` | `(key str) -> Option[str]` | первое значение `?key=value`, percent-декодировано |
| `@body_bytes` | `() -> []u8` | буферизованное тело запроса |

Тело запроса к моменту, когда его видит хендлер, всегда полностью
буферизовано (CORE-объём, `[M-178-server-typed-body]`) — стриминговых тел
запроса пока нет, поэтому его чтение не содержит точки await/park.

## Конструкторы `ServerResponse`

```nova
test "handlers-response: ServerResponse constructors — text/html/bytes/empty/redirect" {
    ro t = ServerResponse.text(StatusCode.OK, "hi")
    assert(hdr(t, "Content-Type").contains("text/plain"))
    ro h = ServerResponse.html(StatusCode.OK, "<b>hi</b>")
    assert(hdr(h, "Content-Type").contains("text/html"))
    ro b = ServerResponse.bytes(StatusCode.OK, "application/octet-stream", [1, 2, 3])
    assert(b.body.len() == 3)
    ro e = ServerResponse.empty(StatusCode.NO_CONTENT)
    assert(e.status_code() == 204)
    ro r = ServerResponse.redirect(StatusCode.FOUND, "/elsewhere")
    assert(hdr(r, "Location") == "/elsewhere")
}
```

| Конструктор | Тело / заголовки |
|---|---|
| `.text(status, s)` | `s`, `Content-Type: text/plain; charset=utf-8` |
| `.html(status, s)` | `s`, `Content-Type: text/html; charset=utf-8` |
| `.bytes(status, content_type, data)` | `data`, заданный `Content-Type` |
| `.empty(status)` | без тела — `204`/`304`/… |
| `.redirect(status, location)` | без тела, `Location: <location>` |
| `.json[T Serialize](status, v)` | `v`, закодированный в JSON, `Content-Type: application/json` (см. [`Json[T]`](#intoresponse)) |
| `.stream(status, headers, producer)` / `.sse(producer)` | chunked/SSE-тело — см. [serving.md](serving.ru.md#streaming-и-sse) |

У каждого статус-принимающего конструктора есть также **устаревшая**
перегрузка на голом `int` (`ServerResponse.text(200, "ok")`) — мост
soft-миграции поверх `unsafe { StatusCode.new_unchecked(status) }`; новый код
должен использовать типизированную `StatusCode`-форму (`StatusCode.OK`, или
`StatusCode.new(code)` для динамического значения — см.
[`StatusCode`](#statuscode) ниже).

После построения ответ декорируется fluent-методами: `resp.header(name, value)`
(мутация на месте, chainable), `resp.body(data)` (замена фиксированного
тела), `resp.status()`/`.status_code()` (типизированное / голое `int`-чтение).

## `IntoResponse`

```nova
export type IntoResponse protocol {
    consume @into_response() -> ServerResponse
}
```

Всё, что хендлер может вернуть, сходится сюда — по духу тот же `IntoResponse`
из Axum'а. Встроенные реализации:

| Тип | Становится |
|---|---|
| `ServerResponse` | сам собой (identity) |
| `str` | `200 OK`, `text/plain` |
| `StatusCode` | ответ без тела с этим статусом |
| `Json[T Serialize]` | `200 OK`, `application/json` |
| любой `T Serialize` (бланкет) | `200 OK`, `application/json` — `Ok(user)` не нуждается в обёртке `Json{}` |
| `HttpError` | смаппленный статус + структурированное JSON-тело ошибки — см. [errors.md](errors.ru.md) |
| `Result[R IntoResponse, E IntoResponse]` (бланкет) | собственный `.into_response()` у `Ok`/`Err` |

Бланкет `Result[R, E]` — то, что даёт `?`-эргономику вспомогательной функции
рядом с хендлером: пишем fallible-логику как обычную функцию, возвращающую
`Result[T, HttpError]`, а затем `.into_response()` схлопывает её:

```nova
fn find_widget(id str) -> Result[str, HttpError] {
    if id == "1" { Ok("widget-one") } else { Err(HttpError.new(Status(StatusCode.NOT_FOUND))) }
}

test "handlers-response: IntoResponse — str/StatusCode/Result[R,E] blanket" {
    assert("hi".into_response().status_code() == 200)
    assert(StatusCode.NOT_FOUND.into_response().status_code() == 404)
    assert(find_widget("1").into_response().status_code() == 200)
    assert(find_widget("nope").into_response().status_code() == 404)
}
```

`json(v)` оборачивает значение в `Json[T]` для ответной стороны
(`json(user).into_response()`, либо `ServerResponse.json(status, v)` для
JSON-ответа с выбранным статусом одним вызовом); `Json[T]` — **тот же** тип,
что извлекается из тела запроса — см. ниже.

## Типизированное извлечение: `FromRequest`

```nova
export type FromRequest protocol {
    .from_request(req ServerRequest) -> Result[Self, HttpError]
}
```

Шесть встроенных extractors его реализуют — каждый однополевая
value-обёртка с аксессором `@data()`:

| Тип | Источник | Как декодируется |
|---|---|---|
| `PathParam[T]` | совпавшие `{name}`-сегменты | serde, по имени поля |
| `Query[T]` | `?a=1&b=2` | serde, по имени поля |
| `Json[T]` | тело запроса | serde JSON |
| `Bytes` | тело запроса | никак — сырой `[]u8`, никогда не отказывает |
| `Text` | тело запроса | UTF-8-декод |
| `Headers` | заголовки запроса | никак — сама `HeaderMap`, никогда не отказывает |

`PathParam[T]`/`Query[T]` переиспользуют собственный `serde` Nova как движок
десериализации (`ParamsDeserializer`/`QueryDeserializer` — новые *источники*
`Deserializer`, а не отдельный самописный парсер): **один** `PathParam[T]`
извлекает столько `{name}`-сегментов, сколько нужно route'у, как поля
записи `T`, сопоставляемые по имени (field-атрибуты `rename` работают так
же, как для любого другого типа с `#impl(Deserialize)`). То же самое — для
`Query[T]` при многоключевой query-строке.

**Сегодняшний канон** — вызывать `T.from_request(req)` вручную,
композируя внутри обычного `Handler`; сахара, позволяющего хендлеру принимать
`PathParam[T]`/`Query[T]`/`Json[T]` как голые параметры функции (форма Axum'а
`async fn handler(Path(id): Path<u32>, Json(body): Json<T>)`), пока **нет**.
Почему — и что должно это разблокировать — см. [roadmap.md](roadmap.ru.md).

```nova
#impl(Serialize + Deserialize)
type WidgetId value { ro id int }

#impl(Serialize + Deserialize)
type WidgetQuery value { ro q str }

#impl(Serialize + Deserialize)
type Widget value { ro name str }

test "handlers-response: typed extractors — PathParam/Query/Json via FromRequest" {
    mut r = Router.new()
    r.post("/widgets/{id}", fn(req ServerRequest) -> ServerResponse {
        match PathParam[WidgetId].from_request(req) {
            Ok(p) => match Query[WidgetQuery].from_request(req) {
                Ok(q) => match Json[Widget].from_request(req) {
                    Ok(j)  => ServerResponse.text(StatusCode.OK, "id=${p.data().id} q=${q.data().q} name=${j.data().name}")
                    Err(e) => e.into_response()
                }
                Err(e) => e.into_response()
            }
            Err(e) => e.into_response()
        }
    })!!
    ro raw = "POST /widgets/7?q=hi HTTP/1.1\r\nHost: n\r\nContent-Type: application/json\r\nContent-Length: 15\r\n\r\n{\"name\":\"nut\"}".bytes()
    ro wire = serve_once(r, raw)
    assert(wire_str(wire).contains("id=7 q=hi name=nut"))
}
```

Любой отказ extractor'а — плохое int-значение в path-параметре, битый JSON,
отсутствующее поле — типизированная `HttpError` (обычно `400`), никогда не
крэш; `e.into_response()` превращает её в то же структурированное тело
ошибки, что описывает [errors.md](errors.ru.md). Собственный doc-comment
extractor'а называет точный отказ, который он маппит.

> **О наименовании.** `PathParam[T]` — временное имя того, что в дизайне
> называется `Path[T]` (паритет с Axum) — переименовано в `PathParam[T]`
> только потому, что `Path` сейчас коллидирует с `std.fs.Path` в некоторых
> компил-юнитах (дефект кросс-модульного тайпчека по имени, отслеживается
> выше по потоку). Как только это починят, `PathParam[T]` станет `Path[T]`,
> а `PathParam[T]` исчезнет — переименование, не новый тип, поведение не
> меняется.

## `Bytes`/`Text`/`Headers`

Три extractor'а, которые никогда не отказывают на корректном входе:

```nova
test "handlers-response: Bytes/Text/Headers extractors never fail on well-formed input" {
    mut r = Router.new()
    r.post("/raw", fn(req ServerRequest) -> ServerResponse {
        ro n = Bytes.from_request(req)!!.data().len()
        ro t = Text.from_request(req)!!.data()
        ro has_host = Headers.from_request(req)!!.data().get("Host").is_some()
        ServerResponse.text(StatusCode.OK, "n=${n} t=${t} host=${has_host}")
    })!!
    ro wire = serve_once(r, post_req("/raw", "hi"))
    assert(wire_str(wire).contains("n=2 t=hi host=true"))
}
```

`Bytes.from_request` бесотказен (`Result` только потому, что этого требует
протокол — всегда `Ok`); `Text.from_request` всё же может отказать на
невалидном UTF-8.

## `multipart/form-data`

`Multipart` (RFC 7578, буферизованный — всё тело уже в памяти по дизайну
лимитов из 228) единообразно парсит и поля, и загрузки файлов как `Part`:

```nova
test "handlers-response: multipart/form-data — fields and file uploads" {
    mut r = Router.new()
    r.post("/upload", fn(req ServerRequest) -> ServerResponse {
        match Multipart.from_request(req) {
            Ok(mp) => {
                ro name = match mp.field("name") { Some(p) => p.text() ?? "?", None => "?" }
                ro has_file = mp.file("avatar").is_some()
                ServerResponse.text(StatusCode.OK, "name=${name} has_file=${has_file}")
            }
            Err(e) => e.into_response()
        }
    })!!
    ro boundary = "X-boundary"
    ro body = "--${boundary}\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\nnova\r\n--${boundary}\r\nContent-Disposition: form-data; name=\"avatar\"; filename=\"a.png\"\r\nContent-Type: image/png\r\n\r\nBINARY\r\n--${boundary}--\r\n"
    ro raw = "POST /upload HTTP/1.1\r\nHost: n\r\nContent-Type: multipart/form-data; boundary=${boundary}\r\nContent-Length: ${body.byte_len()}\r\n\r\n${body}".bytes()
    ro wire = serve_once(r, raw)
    assert(wire_str(wire).contains("name=nova has_file=true"))
}
```

`Multipart.@field(name)` возвращает первую часть с этим именем;
`Multipart.@fields(name)` — все такие части (повторяющиеся поля —
чекбоксы, multi-select); `Multipart.@file(name)` — первая часть с этим
именем, которая *ещё и* несёт `filename` (то есть является загрузкой, а не
обычным полем).

Каждый парс ограничен `MultipartLimits` (по умолчанию 256 частей / 8 МиБ на
часть / 32 МиБ суммарно — `HttpError.body_too_large()` → `413` при
превышении любого лимита, никогда не неограниченный рост буфера);
production-серверы прокидывают собственные лимиты через `ServerPolicy` —
см. [serving.md](serving.ru.md).

## `StatusCode`

```nova
test "handlers-response: StatusCode — named constants, validated new(), unsafe new_unchecked" {
    assert(StatusCode.OK.code() == 200)
    assert(StatusCode.NOT_FOUND.code() == 404)
    assert(match StatusCode.new(999) { Err(_) => true, Ok(_) => false })
    ro weird = unsafe { StatusCode.new_unchecked(799) }
    assert(weird.code() == 799)
}
```

`StatusCode` — value-newtype над `int`, диапазон `100..599`. Частые значения
— именованные вне-тела константы (`StatusCode.OK`, `.CREATED`, `.NO_CONTENT`,
`.BAD_REQUEST`, `.NOT_FOUND`, `.METHOD_NOT_ALLOWED`, `.TOO_MANY_REQUESTS`,
`.INTERNAL_SERVER_ERROR`, …, `status.nv` ядра `http`); `StatusCode.new(code)`
валидирует и возвращает `Result[StatusCode, HttpError]` для динамического
значения; `unsafe { StatusCode.new_unchecked(code) }` полностью пропускает
валидацию (тот самый эскейп-люк, на котором изнутри построены все перегрузки
с голым `int` — в новом коде предпочитайте валидированные формы).

## Связанные документы

**Полный пример:** [`examples/03-json-api`](../examples/03-json-api) — `Json[T]`/`ServerResponse.json`/`IntoResponse` в настоящем REST CRUD-сервисе.

- [routing.md](routing.ru.md) — где регистрируются `Handler`'ы
- [middleware.md](middleware.ru.md) — обёртывание `Handler`
- [errors.md](errors.ru.md) — маппинг статуса/тела у `HttpError` целиком
- [roadmap.md](roadmap.ru.md) — сахар arity-перегрузок для extractors (запланировано)
- [`src/server.nv`](../src/server.nv), [`src/response.nv`](../src/response.nv), [`src/extract.nv`](../src/extract.nv), [`src/multipart.nv`](../src/multipart.nv)
