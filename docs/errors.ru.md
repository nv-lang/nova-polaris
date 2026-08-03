# Ошибки

[English](errors.md) | **Русский**

`HttpError` — единственный структурный тип ошибки для всего стека
`http`/Polaris (и клиент, и сервер) — каждая fallible-операция возвращает
`Result[T, HttpError]`. Эта страница смотрит на него через призму сервера:
как значение, которое строят/получают обработчики, превращается в ответ на
проводе.

Исходник: `HttpError`/`ErrorKind` — `src/error.nv` пакета
[nova-http](https://github.com/nv-lang/nova-http); серверный маппинг —
[`src/response.nv`](../src/response.nv).

---

## Содержание

- [`HttpError` → `ServerResponse`](#httperror--serverresponse)
- [Маппинг статусов](#маппинг-статусов)
- [Прикрепление контекста: `@with_url`](#прикрепление-контекста-with_url)
- [`?`-эргономика через бланкет `Result`](#-эргономика-через-бланкет-result)
- [Паника vs `Fail`: что для чего](#паника-vs-fail-что-для-чего)
- [Связанные документы](#связанные-документы)

---

## `HttpError` → `ServerResponse`

```nova
test "errors: HttpError.into_response() maps ErrorKind to a status + structured JSON body" {
    ro resp = HttpError.protocol_error("bad shape").into_response()
    assert(resp.status_code() == 400)
    ro body = unsafe { resp.body.to_str_unchecked() }
    assert(body.contains("\"error\":\"protocol\""))
    assert(body.contains("\"message\""))

    assert(HttpError.body_too_large().into_response().status_code() == 413)
    assert(HttpError.new(Status(StatusCode.FORBIDDEN)).into_response().status_code() == 403)
}
```

Реализация `#impl(IntoResponse)` у `HttpError` (см.
[handlers-response.md](handlers-response.ru.md#intoresponse)) маппит его и в
статус, **и** в структурированное JSON-тело — форма в духе FastAPI, не
голый текст:

```json
{"error": "<kind-name>", "message": "<HttpError.to_str()>"}
```

`<kind-name>` — короткий тег в нижнем регистре (`"protocol"`,
`"invalid_url"`, `"body_too_large"`, `"blocked"`, `"other"`, …) —
стабильный, пригодный для сопоставления и отличный от `message`, который —
свободный человекочитаемый текст (ориентирован на логи — не полагайтесь на
его точную формулировку).

## Маппинг статусов

| `ErrorKind` | Статус |
|---|---|
| `Connect`, `Dns`, `Tls`, `Timeout`, `Closed`, `Canceled` | `503 Service Unavailable` |
| `Protocol(_)`, `InvalidUrl`, `InvalidHeader` | `400 Bad Request` |
| `Status(c)` | эхом отдаёт `c` как есть |
| `TooManyRedirects(_)`, `Other(_)` | `500 Internal Server Error` |
| `BodyTooLarge` | `413 Payload Too Large` |
| `Blocked(_)` | `403 Forbidden` |

Большинство transport-класса kind'ов (`Connect`/`Dns`/`Tls`/`Timeout`/…)
приходят с клиентской стороны `http` (обработчик Polaris вызывает другой
сервис через `HttpClient`, и этот вызов падает) — обработчик, проксирующий
такой вызов и возвращающий получившуюся `HttpError`, получает разумный
`503` бесплатно, без ручного маппинга. `ErrorKind` — **открытый**
(`Other(str)` — catch-all) — `match` по нему всегда обязан нести
wildcard-arm, поэтому добавление нового kind'а позже не ломает совместимость.

## Прикрепление контекста: `@with_url`

`e.with_url(u)` (из ядра `http`) прикрепляет `Url` к ошибке для более
богатых логов/диагностики на границе клиентского вызова — маппинг статуса
выше от этого не меняется; это только метаданные, читаются через
`HttpError.url`.

## `?`-эргономика через бланкет `Result`

```nova
fn lookup(id str) -> Result[str, HttpError] {
    if id == "1" { Ok("found") } else { Err(HttpError.new(Status(StatusCode.NOT_FOUND))) }
}

test "errors: a plain Result[T, HttpError] helper composes into a handler via the blanket" {
    mut r = Router.new()
    r.get("/items/{id}", fn(req ServerRequest) -> ServerResponse =>
        lookup(req.param("id") ?? "").into_response())!!

    assert(status_line(serve_once(r, get_req("/items/1"))) == "HTTP/1.1 200 OK")
    assert(status_line(serve_once(r, get_req("/items/9"))) == "HTTP/1.1 404 Not Found")
}
```

Поскольку `HttpError` (как и `str`, и любой `T Serialize`) реализует
`IntoResponse`, бланкет
`Result[R IntoResponse, E IntoResponse] : IntoResponse` означает, что
обычная вспомогательная функция, возвращающая `Result[T, HttpError]` —
написанная с обычным `?`-пробросом внутри, без единого `ServerResponse` в
поле зрения — встаёт прямо в обработчик одним вызовом `.into_response()` на
границе. Это идиоматичная форма для логики обработки запроса в Polaris:
держите доменные функции возвращающими `Result[T, HttpError]`, а
построение `ServerResponse` — на самой границе.

## Паника vs `Fail`: что для чего

До обработчика доходят два разных канала отказа, и Polaris намеренно
обращается с ними по-разному (222.20 Ф.3 Волна C):

- **Ожидаемые, восстановимые исходы** (не найдено, плохой ввод,
  не авторизован, апстрим вернул 503, …) — это **`Result[T, HttpError]`**,
  см. бланкет выше. Дефолтный канал для всего, что предвидит сама логика
  обработчика.
- **Программные ошибки и по-настоящему неожиданные отказы** (assert,
  выход за границы, ускользнувший `Fail`-throw из тела обработчика) — это
  **паника/ускользнувший throw**. Polaris НЕ требует оборачивать каждый
  мыслимый дефект в `Result` — per-request Stop-supervision (D416) ловит
  их на границе соединения:

```nova
ro app = build_router()
// ServerPolicy.panic_response(): InternalError500 (default) writes a
// generic 500 and keeps the connection alive for the NEXT request on it;
// Close drops the connection with no response body instead.
serve_router(listener, app, ServerPolicy.new())
```

  Пойманная паника/throw логируется один раз через ambient-эффект `Log`
  (`"handler panic: <message>"`) и получает ответ по `ServerPolicy.
  panic_response()` — `InternalError500` (дефолт) или `Close`.
  **Только сообщение, намеренно** (D437): полная диагностика рантайма
  «сообщение + место throw + трасса распространения» печатается ТОЛЬКО
  на верхнеуровневом необработанном abort-пути — у Nova нет доступа к
  трассе из `Supervisor`-обработчика, поэтому recover-500 честно логирует то,
  что реально есть (сообщение через `err.try_as[str]()`), а не выдуманное
  «место».

**Практическое правило:** если ваш код способен заранее назвать режим
отказа — верните его как `Result[T, HttpError]`. Если не способен —
настоящий баг, нарушение инварианта, паника зависимости — пусть паникует;
recover-500 сдерживает радиус поражения одним запросом, процесс (и все
остальные соединения в полёте) продолжает работать.

## Связанные документы

**Полный пример:** [`examples/03-json-api`](../examples/03-json-api) — `HttpError`/`StatusCode` и blanket `Result[T, HttpError]`, реально запущенные.

- [handlers-response.md](handlers-response.ru.md) — `IntoResponse` целиком, режимы отказа extractors
- [auth.md](auth.ru.md) — `401` от extractors Bearer/Basic/JWT, тот же маппинг
- Сами `HttpError`/`ErrorKind` — собственный `src/error.nv` пакета [nova-http](https://github.com/nv-lang/nova-http)
- [`src/response.nv`](../src/response.nv), [`src/response_test.nv`](../src/response_test.nv)
