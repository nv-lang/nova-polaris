# Extractors

**English** | [Русский](extractors.ru.md)

An **extractor** pulls a typed value out of a `ServerRequest` instead of a
handler hand-parsing bytes/strings itself — Axum's own `FromRequest` idea,
one protocol method: `.from_request(req) -> Result[Self, HttpError]`. This
page covers the extractor family end to end: the base protocol, the six
built-in extractors, the bare-type sugar that lets a plain domain type
declare its own extraction source, and the **typed-route** registration
methods (`TypedRoute`/`*_typed`/`*_typed_h`) that wire an extractor straight
into `Router` — including how the shapes they carry feed OpenAPI generation.

Source: [`src/extract.nv`](../src/extract.nv) (`FromRequest`/`FromPath`/
`FromQuery`/`FromBody` + built-in extractors + typed-route registration),
[`src/response.nv`](../src/response.nv) (`Json[T]`), [`src/server.nv`](../src/server.nv)
(`Req`), [`src/openapi.nv`](../src/openapi.nv) (the OpenAPI emitter these
shapes feed).

---

## Contents

- [`FromRequest`: the base protocol](#fromrequest-the-base-protocol)
- [Built-in extractors](#built-in-extractors)
- [A failed extractor short-circuits to a response](#a-failed-extractor-short-circuits-to-a-response)
- [Bare-type sugar: `FromPath` / `FromQuery` / `FromBody`](#bare-type-sugar-frompath--fromquery--frombody)
- [Typed routes: `TypedRoute` + `*_typed`](#typed-routes-typedroute--_typed)
- [Bare-sugar registration: `*_typed_h`](#bare-sugar-registration-_typed_h)
- [Connection to OpenAPI](#connection-to-openapi)
- [Known ceremony: `.data()`](#known-ceremony-data)
- [Related documents](#related-documents)

---

## `FromRequest`: the base protocol

```nova
export type FromRequest protocol {
    .from_request(req ServerRequest) -> Result[Self, HttpError]
}
```

Always synchronous — unlike Axum's `async fn from_request`, a Polaris
request body is already fully buffered by the time a handler sees it (see
[handlers-response.md](handlers-response.md#serverrequest)), so there is no
await point in extraction at all.

## Built-in extractors

Six types implement `FromRequest` — each a one-field value wrapper with a
`@data()` property accessor (see [Known ceremony: `.data()`](#known-ceremony-data)
for why the accessor exists instead of a bare field):

| Type | Source | Decoded via |
|---|---|---|
| `PathParam[T]` | matched `{name}` path segment(s) | serde, by field name |
| `Query[T]` | `?a=1&b=2` query string | serde, by field name |
| `Json[T]` | request body | serde JSON |
| `Bytes` | request body | none — raw `[]u8`, never fails |
| `Text` | request body | UTF-8 decode |
| `Headers` | request headers | none — the `HeaderMap`, never fails |
| `Req` | the whole request | none — passthrough, never fails |

`PathParam[T]`/`Query[T]`/`Json[T]` reuse Nova's own `serde` as the
deserialization engine — `ParamsDeserializer`/`QueryDeserializer` are new
`Deserializer` *sources* over flat key/value pairs, driving the same
compiler-synthesized `T.deserialize(d)` that JSON bodies use. **One**
`PathParam[T]` extracts as many `{name}` segments as a route has, as fields
of a record `T` matched by name (`#serde(rename)` works the same as any
other `#impl(Deserialize)` type); the same applies to `Query[T]` for
multi-key query strings.

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

`Json[T]` is the *same* type used on the response side too — see
[handlers-response.md](handlers-response.md#intoresponse) for `json(v)`/
`ServerResponse.json(status, v)`.

> **Note on naming.** `PathParam[T]` is a temporary name for what the design
> calls `Path[T]` — `Path` currently collides with `std.fs.Path` in some
> compile units (a compiler defect, tracked upstream); it will be renamed
> back to `Path[T]` once that closes. No behavior differs.

## A failed extractor short-circuits to a response

Every extractor failure — a bad int in a path param, malformed JSON, a
missing field — is a typed `HttpError` (usually `400`), never a crash.
Calling `.from_request` by hand (as above) means *you* write the
short-circuit with `match`/`?`; the [typed-route registrars](#typed-routes-typedroute--_typed)
below do it for you: **the first extraction `Err` goes straight to
`e.into_response()` — the handler function itself is never called.** This
is the same rule a bundle type's own hand-written `#impl(FromRequest)`
follows when it composes several sources with `?` (see the next section) —
short-circuit on read, not on write.

## Bare-type sugar: `FromPath` / `FromQuery` / `FromBody`

Axum-**better**-than-parity form: instead of a handler parameter being
wrapped (`PathParam[UserId]`, `Query[Filter]`, `Json[Body]`) with `.data()`
unwrapping at every use, a plain domain type declares its **own**
extraction source once, via one of three narrower protocols:

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

A type normally forwards its impl straight to the matching wrapper's own
`from_request` (`NoteIdParam.from_path` delegates to
`PathParam[NoteIdParam].from_request`, etc. — see the runnable example
below); the wrapper family above remains the legal *explicit* form and the
escape hatch for a type that legitimately needs more than one source across
different routes (a type implementing **two** of `FromPath`/`FromQuery`/
`FromBody` has no single honest default, so route it through the explicit
wrapper instead of bare-type sugar).

Several bare types compose into **one bundle record** — a hand-written
`#impl(FromRequest)` extracts each field in declaration order with `?`,
which is exactly the short-circuit rule from the section above: the first
field to fail returns immediately, the remaining fields (and the handler)
never run.

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

This is a real-world pattern, not a toy — see
[`examples/03-json-api`](../examples/03-json-api)'s `POST /todos/{id}/note`
route for the exact same shape (`TodoIdParam`=path, `NoteQuery`=query,
`NoteBody`=body, bundled into `AddNoteReq`).

## Typed routes: `TypedRoute` + `*_typed`

```nova
export type TypedRoute value {
    ro handler    Handler
    ro req_shape  Option[TypeShape]
    ro resp_shape Option[TypeShape]
}
```

The low-level typed-registration form: build a `TypedRoute` — a plain
`Handler` closure (written the same way as any other route in this doc set)
plus the request/response `TypeShape`s you want `Router.introspect()` to
report — and register it with `Router.mut @get_typed`/`@post_typed`/
`@put_typed`/`@delete_typed`/`@patch_typed(path, t)`. Each is sugar over the
matching plain `@get`/`@post`/…(`path, t.handler)` call that **additionally**
records `t.req_shape`/`t.resp_shape` for introspection — no other behavior
difference from a plain route.

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

A route registered the plain way (`@get`/`@post`/…/`@route`, no `_typed`
suffix) still shows up in `Router.introspect()` — just honestly with
`req_shape: None, resp_shape: None` ("schema unknown", never guessed).

## Bare-sugar registration: `*_typed_h`

```nova
export fn Router mut @post_typed_h[T FromRequest + Reflect](path str, h fn(T) -> ServerResponse) -> Result[Router, HttpError]
```

The ergonomic form used in the [bundle example](#bare-type-sugar-frompath--fromquery--frombody)
above: pass a **bare** handler `h fn(T) -> ServerResponse` plus one type
parameter `T`, and `@post_typed_h` composes the `TypedRoute` adapter for
you — `T.from_request(req)` on the way in (first `Err` short-circuits to
`e.into_response()`, per [above](#a-failed-extractor-short-circuits-to-a-response)),
`Some(T.reflect())` recorded as the request shape. Today only
`@post_typed_h` exists (the family this package's own registration surface
grew for its bundle-body use case); the other four HTTP methods stay on the
`TypedRoute`-literal form above until a matching `@get_typed_h`/etc. lands.
This is a **separate method name** from `@post_typed`/`@post`, not an
overload — Nova's own arity-overload codegen has an open gap that makes a
same-named bound-generic overload break unrelated non-generic call sites of
the same method (see [roadmap.md](roadmap.md#extractor-arity-overload-sugar)
for the compiler defect this sidesteps — that page also covers the closely
related, still-blocked `Router.@get[T1, R](path, h)`-shaped sugar directly
on the *existing* method names).

## Connection to OpenAPI

`T.reflect()` (from [`std.reflect`](../../nova/std/src/reflect.nv),
`Reflect` protocol) describes a type's structural shape as a `TypeShape` —
format-independent, no HTTP/JSON in it at all. The extractor wrappers each
carry a manual `Reflect` impl that tags their shape with the wrapper's own
type name (`Record("PathParam", [("data", ..)])`, `Record("Query", ..)`,
`Record("Json", ..)`) — that name is exactly what
[`src/openapi.nv`](../src/openapi.nv)'s emitter reads to decide a bundle
field's role (`parameters[in=path]` / `parameters[in=query]` /
`requestBody`) when it walks `Router.introspect()`'s `req_shape`/
`resp_shape`. The whole pipeline, end to end: a bundle type's `#impl(Reflect)`
→ `Some(T.reflect())` stored as `TypedRoute.req_shape` (or produced
automatically by `@post_typed_h`) → `Router.introspect() -> []RouteInfo` →
`openapi_json(routes, title, version)`/`openapi_handler(routes, title,
version)` render an OpenAPI 3.0 JSON document from those shapes directly —
no intermediate schema type. Wiring `/openapi.json` itself is always
explicit registration (`r.get("/openapi.json", openapi_handler(r.introspect(),
..))!!`, shown in the test above) — never automatic inside `serve_router`.

## Known ceremony: `.data()`

Every wrapper extractor (`PathParam[T]`/`Query[T]`/`Json[T]`/`Bytes`/`Text`/
`Headers`) holds its decoded value behind a private field and a `@data()`
property accessor rather than a public bare field — reading `p.data().id`
instead of `p.id` is today's required ceremony. This is expected to
shrink once backlog item №147 (`D39-embed` — using Nova's `use Type`
struct-embedding delegation, [spec D39](https://github.com/nv-lang/nova/blob/main/spec/decisions/02-types.md#d39))
lands, letting a wrapper delegate field access straight through to the
inner value; no target date is promised here.

## Related documents

**Full example:** [`examples/03-json-api`](../examples/03-json-api) — the
bare-type bundle + `post_typed_h` pattern in a real REST CRUD service, plus
`/openapi.json` wired up for real (compare against its
[`openapi.golden.json`](../examples/03-json-api/openapi.golden.json)).

- [handlers-response.md](handlers-response.md) — `ServerRequest`/`ServerResponse`/`IntoResponse`, the request/response half `FromRequest` complements
- [routing.md](routing.md#typed-routes) — where typed routes fit among the plain registration forms
- [errors.md](errors.md) — `HttpError`'s own status/body mapping, what every extractor failure becomes
- [roadmap.md](roadmap.md#extractor-arity-overload-sugar) — the still-blocked same-name arity-overload sugar directly on `@get`/`@post`/…
- [`src/extract.nv`](../src/extract.nv), [`src/extract_test.nv`](../src/extract_test.nv), [`src/openapi.nv`](../src/openapi.nv)
