# Экстракторы

[English](extractors.md) | **Русский**

**Экстрактор** извлекает типизированное значение из `ServerRequest` вместо
того, чтобы обработчик сам вручную парсил байты/строки — идея `FromRequest` из
Axum'а, один метод протокола: `.from_request(req) -> Result[Self, HttpError]`.
Эта страница покрывает семейство экстракторов целиком: базовый протокол,
шесть встроенных экстракторов, голый-типовой сахар, позволяющий обычному
доменному типу самому объявлять свой источник извлечения, и методы
регистрации **typed-маршрутов** (`TypedRoute`/`*_typed`/`*_typed_h`),
которые подключают экстрактор прямо к `Router` — включая то, как несомые
ими шэйпы питают генерацию OpenAPI.

Исходник: [`src/extract.nv`](../src/extract.nv) (`FromRequest`/`FromPath`/
`FromQuery`/`FromBody` + встроенные экстракторы + регистрация typed-маршрутов),
[`src/response.nv`](../src/response.nv) (`Json[T]`), [`src/server.nv`](../src/server.nv)
(`Req`), [`src/openapi.nv`](../src/openapi.nv) (эмиттер OpenAPI, который
питают эти шэйпы).

---

## Содержание

- [`FromRequest`: базовый протокол](#fromrequest-базовый-протокол)
- [Встроенные экстракторы](#встроенные-экстракторы)
- [Отказавший экстрактор коротко замыкает на ответ](#отказавший-экстрактор-коротко-замыкает-на-ответ)
- [Голый-типовой сахар: `FromPath` / `FromQuery` / `FromBody`](#голый-типовой-сахар-frompath--fromquery--frombody)
- [Typed-маршруты: `TypedRoute` + `*_typed`](#typed-маршруты-typedroute--_typed)
- [Bare-sugar регистрация: `*_typed_h`](#bare-sugar-регистрация-_typed_h)
- [Связь с OpenAPI](#связь-с-openapi)
- [Известная церемония: `.data()`](#известная-церемония-data)
- [Связанные документы](#связанные-документы)

---

## `FromRequest`: базовый протокол

```nova
export type FromRequest protocol {
    .from_request(req ServerRequest) -> Result[Self, HttpError]
}
```

Всегда синхронный — в отличие от Axum'овского `async fn from_request`, тело
запроса в Polaris к моменту, когда его видит обработчик, уже полностью
буферизовано (см. [handlers-response.md](handlers-response.ru.md#serverrequest)),
поэтому в извлечении вообще нет точки await.

## Встроенные экстракторы

Шесть типов реализуют `FromRequest` — каждый однополевая value-обёртка с
аксессором-свойством `@data()` (почему аксессор, а не голое поле — см.
[Известная церемония: `.data()`](#известная-церемония-data)):

| Тип | Источник | Как декодируется |
|---|---|---|
| `PathParam[T]` | совпавший(ие) `{name}`-сегмент(ы) пути | serde, по имени поля |
| `Query[T]` | query-строка `?a=1&b=2` | serde, по имени поля |
| `Json[T]` | тело запроса | serde JSON |
| `Bytes` | тело запроса | никак — сырой `[]u8`, никогда не отказывает |
| `Text` | тело запроса | UTF-8-декод |
| `Headers` | заголовки запроса | никак — сама `HeaderMap`, никогда не отказывает |
| `Req` | весь запрос | никак — passthrough, никогда не отказывает |

`PathParam[T]`/`Query[T]`/`Json[T]` переиспользуют собственный `serde` Nova
как движок десериализации — `ParamsDeserializer`/`QueryDeserializer` — новые
*источники* `Deserializer` над плоскими парами ключ/значение, гоняющие тот
же компилятором синтезированный `T.deserialize(d)`, что и тела JSON.
**Один** `PathParam[T]` извлекает столько `{name}`-сегментов, сколько нужно
route'у, как поля записи `T`, сопоставляемые по имени (`#serde(rename)`
работает так же, как для любого другого типа с `#impl(Deserialize)`); то же
самое — для `Query[T]` при многоключевой query-строке.

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

`Json[T]` — **тот же** тип, что используется на ответной стороне — см.
[handlers-response.md](handlers-response.ru.md#intoresponse) про `json(v)`/
`ServerResponse.json(status, v)`.

> **О наименовании.** `PathParam[T]` — временное имя того, что в дизайне
> называется `Path[T]` — `Path` сейчас коллидирует с `std.fs.Path` в
> некоторых компил-юнитах (дефект компилятора, отслеживается выше по
> потоку); переименуется обратно в `Path[T]`, как только это закроется.
> Поведение не меняется.

## Отказавший экстрактор коротко замыкает на ответ

Любой отказ экстрактора — плохое int-значение в path-параметре, битый JSON,
отсутствующее поле — типизированная `HttpError` (обычно `400`), никогда не
крэш. Ручной вызов `.from_request` (как выше) означает, что короткое
замыкание пишете *вы сами* через `match`/`?`; [регистраторы typed-маршрутов](#typed-маршруты-typedroute--_typed)
ниже делают это за вас: **первый `Err` при извлечении сразу уходит в
`e.into_response()` — сама функция-обработчик не вызывается вовсе.** Это то
же правило, которому следует собственный рукописный `#impl(FromRequest)`
у типа-бандла, когда он композирует несколько источников через `?` (см.
следующий раздел) — короткое замыкание при чтении, а не при записи.

## Голый-типовой сахар: `FromPath` / `FromQuery` / `FromBody`

Форма **лучше** паритета с Axum: вместо того, чтобы параметр обработчика был
обёрнут (`PathParam[UserId]`, `Query[Filter]`, `Json[Body]`) с разворачиванием
`.data()` на каждом использовании, обычный доменный тип объявляет свой
**собственный** источник извлечения один раз, через один из трёх более
узких протоколов:

```nova
export type FromPath protocol {
    .from_path(req ServerRequest) -> Result[Self, HttpError]
}

export type FromQuery protocol {
    .from_query(req ServerRequest) -> Result[Self, HttpError]
}

export type FromBody protocol {
    .from_body(req ServerRequest) -> Result[Self, HttpError]
}
```

Тип обычно просто форвардит свой impl прямо на `from_request` подходящей
обёртки (`NoteIdParam.from_path` делегирует на
`PathParam[NoteIdParam].from_request` и т.д. — см. рабочий пример ниже);
семейство обёрток выше остаётся легальной *явной* формой и эскейп-люком
для типа, которому реально нужно больше одного источника в разных route'ах
(тип, реализующий **два** из `FromPath`/`FromQuery`/`FromBody`, не имеет
единственного честного дефолта — заводите его через явную обёртку вместо
голого-типового сахара).

Несколько голых типов собираются в **одну запись-бандл** — рукописный
`#impl(FromRequest)` извлекает каждое поле по порядку объявления через `?`
— это ровно то же правило короткого замыкания, что и в разделе выше:
первое отказавшее поле возвращается немедленно, оставшиеся поля (и
обработчик) не выполняются вовсе.

```nova
#impl(Serialize + Deserialize + Reflect)
type NoteIdParam value { ro id int }

#impl(Serialize + Deserialize + Reflect)
type PinFlag value { ro pinned bool }

#impl(Serialize + Deserialize + Reflect)
type NoteBody value { ro text str }

#impl(FromPath)
fn NoteIdParam.from_path(req ServerRequest) -> Result[NoteIdParam, HttpError] =>
    match PathParam[NoteIdParam].from_request(req) { Ok(p) => Ok(p.data()), Err(e) => Err(e) }

#impl(FromQuery)
fn PinFlag.from_query(req ServerRequest) -> Result[PinFlag, HttpError] =>
    match Query[PinFlag].from_request(req) { Ok(q) => Ok(q.data()), Err(e) => Err(e) }

#impl(FromBody)
fn NoteBody.from_body(req ServerRequest) -> Result[NoteBody, HttpError] =>
    match Json[NoteBody].from_request(req) { Ok(j) => Ok(j.data()), Err(e) => Err(e) }

// One bundle record — each field names its OWN source via its OWN type.
// The handler below receives ONE bare `AddNoteReq`, zero wrapper ceremony.
type AddNoteReq value { ro id NoteIdParam, ro opts PinFlag, ro note NoteBody }

#impl(FromRequest)
fn AddNoteReq.from_request(req ServerRequest) -> Result[AddNoteReq, HttpError] {
    Ok(AddNoteReq{
        id: NoteIdParam.from_path(req)?,
        opts: PinFlag.from_query(req)?,
        note: NoteBody.from_body(req)?,
    })
}

// Manual `#impl(Reflect)` — NOT auto-derived: auto-derive's field-walk
// through a generic-wrapper field type (`PathParam[T]` etc. embedded as a
// FIELD of another record) is a known compiler gap. The manual impl
// mirrors exactly what auto-derive WOULD produce for a `{ data T }` struct,
// same field name — see [Connection to OpenAPI](#connection-to-openapi).
#impl(Reflect)
fn AddNoteReq.reflect() -> TypeShape => TypeShape.Record("AddNoteReq", [
    ("id",   TypeShape.Record("PathParam", [("data", NoteIdParam.reflect())])),
    ("opts", TypeShape.Record("Query",     [("data", PinFlag.reflect())])),
    ("note", TypeShape.Record("Json",      [("data", NoteBody.reflect())])),
])

fn add_note(req AddNoteReq) -> ServerResponse =>
    ServerResponse.text(StatusCode.OK, "id=${req.id.id} pinned=${req.opts.pinned} text=${req.note.text}")

test "extractors: FromPath+FromQuery+FromBody bundle registered via bare-sugar post_typed_h; first Err short-circuits" {
    mut r = Router.new()
    r.post_typed_h[AddNoteReq]("/notes/{id}", add_note)!!

    ro body = "{\"text\":\"hi\"}"
    ro raw = "POST /notes/7?pinned=true HTTP/1.1\r\nHost: n\r\nContent-Type: application/json\r\nContent-Length: ${body.byte_len()}\r\n\r\n${body}".bytes()
    assert(wire_str(serve_once(r, raw)).contains("id=7 pinned=true text=hi"))

    // a non-numeric {id} fails the FIRST field's extractor (`NoteIdParam.from_path`)
    // — `add_note` never runs, `PinFlag`/`NoteBody` are never even attempted.
    ro bad = "POST /notes/nope?pinned=true HTTP/1.1\r\nHost: n\r\nContent-Type: application/json\r\nContent-Length: ${body.byte_len()}\r\n\r\n${body}".bytes()
    assert(status_line(serve_once(r, bad)) == "HTTP/1.1 400 Bad Request")
}
```

Это реальный паттерн, не игрушечный — см. route `POST /todos/{id}/note` в
[`examples/03-json-api`](../examples/03-json-api) — ровно та же форма
(`TodoIdParam`=путь, `NoteQuery`=query, `NoteBody`=тело, собраны в
`AddNoteReq`).

## Typed-маршруты: `TypedRoute` + `*_typed`

```nova
export type TypedRoute value {
    ro handler    Handler
    ro req_shape  Option[TypeShape]
    ro resp_shape Option[TypeShape]
}
```

Низкоуровневая форма typed-регистрации: соберите `TypedRoute` — обычное
замыкание `Handler` (написанное так же, как любой другой route в этом
наборе доков) плюс `TypeShape` запроса/ответа, которые должен сообщать
`Router.introspect()` — и зарегистрируйте через `Router.mut @get_typed`/
`@post_typed`/`@put_typed`/`@delete_typed`/`@patch_typed(path, t)`. Каждый —
сахар над обычным `@get`/`@post`/…`(path, t.handler)`, который
**дополнительно** записывает `t.req_shape`/`t.resp_shape` для интроспекции
— никакого другого отличия в поведении от обычного route.

```nova
test "extractors: TypedRoute + Router.@get_typed record shapes; Router.introspect() feeds openapi_handler" {
    mut r = Router.new()
    r.get_typed("/notes/{id}", TypedRoute{
        handler: fn(req ServerRequest) -> ServerResponse {
            match PathParam[NoteIdParam].from_request(req) {
                Ok(p)  => ServerResponse.text(StatusCode.OK, "id=${p.data().id}")
                Err(e) => e.into_response()
            }
        },
        req_shape: Some(PathParam[NoteIdParam].reflect()),
        resp_shape: Some(str.reflect()),
    })!!
    assert(wire_str(serve_once(r, get_req("/notes/9"))).contains("id=9"))

    ro routes = r.introspect()
    r.get("/openapi.json", openapi_handler(routes, "Notes API", "1.0.0"))!!
    ro spec = wire_str(serve_once(r, get_req("/openapi.json")))
    assert(spec.contains("\"openapi\":\"3.0.3\""))
    assert(spec.contains("\"NoteIdParam\""))
}
```

Route, зарегистрированный обычным способом (`@get`/`@post`/…/`@route`, без
суффикса `_typed`), всё равно попадает в `Router.introspect()` — просто
честно с `req_shape: None, resp_shape: None` («схема неизвестна», никогда
не угадывается).

## Bare-sugar регистрация: `*_typed_h`

```nova
export fn Router mut @post_typed_h[T FromRequest + Reflect](path str, h fn(T) -> ServerResponse) -> Result[Router, HttpError]
```

Эргономичная форма, использованная в [примере с бандлом](#голый-типовой-сахар-frompath--fromquery--frombody)
выше: передаётся **голый** обработчик `h fn(T) -> ServerResponse` плюс один
type-параметр `T`, а `@post_typed_h` собирает адаптер `TypedRoute` сам —
`T.from_request(req)` на входе (первый `Err` коротко замыкает на
`e.into_response()`, по [правилу выше](#отказавший-экстрактор-коротко-замыкает-на-ответ)),
`Some(T.reflect())` записывается как шэйп запроса. Сегодня существует
только `@post_typed_h` (семейство, которое выросло у этого пакета под его
собственный кейс тела-бандла); остальные четыре HTTP-метода остаются на
форме `TypedRoute`-литерала выше, пока не появится соответствующий
`@get_typed_h`/т.п. Это **отдельное имя метода** от `@post_typed`/`@post`,
не перегрузка — у собственного кодогена Nova для arity-перегрузок есть
открытый пробел, из-за которого одноимённая bound-generic перегрузка ломает
не связанные с ней не-generic вызовы того же метода (см.
[roadmap.md](roadmap.ru.md#сахар-arity-перегрузок-для-extractors) про
дефект компилятора, который это обходит — эта же страница покрывает тесно
связанный, всё ещё заблокированный сахар вида `Router.@get[T1, R](path, h)`
прямо на *существующих* именах методов).

## Связь с OpenAPI

`T.reflect()` (из [`std.reflect`](../../nova/std/src/reflect.nv), протокол
`Reflect`) описывает структурную форму типа как `TypeShape` — независимо от
формата, вообще без HTTP/JSON внутри. Каждая обёртка-экстрактор несёт
ручной impl `Reflect`, помечающий свой шэйп собственным именем типа-обёртки
(`Record("PathParam", [("data", ..)])`, `Record("Query", ..)`,
`Record("Json", ..)`) — это имя ровно то, что читает эмиттер
[`src/openapi.nv`](../src/openapi.nv), чтобы решить роль поля бандла
(`parameters[in=path]` / `parameters[in=query]` / `requestBody`), обходя
`req_shape`/`resp_shape` из `Router.introspect()`. Весь конвейер целиком: у
типа-бандла `#impl(Reflect)` → `Some(T.reflect())` сохраняется как
`TypedRoute.req_shape` (или производится автоматически `@post_typed_h`) →
`Router.introspect() -> []RouteInfo` → `openapi_json(routes, title,
version)`/`openapi_handler(routes, title, version)` рендерят документ
OpenAPI 3.0 JSON прямо из этих шэйпов — без промежуточного типа схемы.
Подключение `/openapi.json` — всегда явная регистрация
(`r.get("/openapi.json", openapi_handler(r.introspect(), ..))!!`, показано в
тесте выше) — никогда не автоматика внутри `serve_router`.

## Известная церемония: `.data()`

Каждый экстрактор-обёртка (`PathParam[T]`/`Query[T]`/`Json[T]`/`Bytes`/
`Text`/`Headers`) держит своё декодированное значение за приватным полем и
аксессором-свойством `@data()`, а не голым публичным полем — чтение
`p.data().id` вместо `p.id` — сегодняшняя обязательная церемония.
Ожидается, что она уменьшится, когда закроется backlog-пункт №147
(`D39-embed` — использование Nova'вской делегации через struct-embedding
`use Type`, [спека D39](https://github.com/nv-lang/nova/blob/main/spec/decisions/02-types.md#d39)),
позволяющей обёртке делегировать доступ к полю прямо на внутреннее
значение; никакой срок здесь не обещается.

## Связанные документы

**Полный пример:** [`examples/03-json-api`](../examples/03-json-api) —
паттерн голого-типового бандла + `post_typed_h` в настоящем REST
CRUD-сервисе, плюс по-настоящему подключённый `/openapi.json` (сравните с
его [`openapi.golden.json`](../examples/03-json-api/openapi.golden.json)).

- [handlers-response.md](handlers-response.ru.md) — `ServerRequest`/`ServerResponse`/`IntoResponse`, запрос-ответная половина, которую дополняет `FromRequest`
- [routing.md](routing.ru.md#typed-маршруты) — где typed-маршруты вписываются среди обычных форм регистрации
- [errors.md](errors.ru.md) — собственный маппинг статуса/тела у `HttpError`, во что превращается любой отказ экстрактора
- [roadmap.md](roadmap.ru.md#сахар-arity-перегрузок-для-extractors) — всё ещё заблокированный одноимённый сахар arity-перегрузок прямо на `@get`/`@post`/…
- [`src/extract.nv`](../src/extract.nv), [`src/extract_test.nv`](../src/extract_test.nv), [`src/openapi.nv`](../src/openapi.nv)
