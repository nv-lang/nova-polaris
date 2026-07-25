# Handlers, requests, and responses

**English** | [Русский](handlers-response.ru.md)

This page covers the request/response model a handler works with:
`Handler` itself, reading a `ServerRequest`, building a `ServerResponse`,
the `IntoResponse` convergence protocol that lets a handler return more than
just a bare `ServerResponse`, typed extraction via `FromRequest`, and
`StatusCode`.

Source: [`src/server.nv`](../src/server.nv) (`ServerRequest`/`ServerResponse`/`Handler`),
[`src/response.nv`](../src/response.nv) (`IntoResponse`/`Json[T]`),
[`src/extract.nv`](../src/extract.nv) (`FromRequest` + extractors),
[`src/multipart.nv`](../src/multipart.nv).

---

## Contents

- [`Handler`](#handler)
- [`ServerRequest`](#serverrequest)
- [`ServerResponse` constructors](#serverresponse-constructors)
- [`IntoResponse`](#intoresponse)
- [Typed extraction: `FromRequest`](#typed-extraction-fromrequest)
- [`Bytes`/`Text`/`Headers`](#bytestextheaders)
- [`multipart/form-data`](#multipartform-data)
- [`StatusCode`](#statuscode)
- [Related documents](#related-documents)

---

## `Handler`

```nova
export type Handler fn(ServerRequest) -> ServerResponse
```

`Handler` is a newtype over the fn type, **not** an alias (D52/D55): a bare
function or closure auto-lifts into it wherever one is expected — every
`Router.@get`/`@post`/… call in this doc set passes a closure directly, no
`Handler.new(...)`/wrapper call. A `Handler` **value** is called through
directly (`h(req)`), the one operation that makes sense for a wrapped
function — the same shape as Go's `http.HandlerFunc`.

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

| Method | Signature | Notes |
|---|---|---|
| `@method` | `() -> Method` | request method |
| `@path` | `() -> str` | decoded path, query stripped |
| `@target` | `() -> str` | raw request-target (`path[?query]`) |
| `@headers` | `() -> HeaderMap` | full header map |
| `@header` | `(name str) -> Option[str]` | first value, case-insensitive |
| `@param` | `(name str) -> Option[str]` | a matched `{name}` path segment |
| `@query_param` | `(key str) -> Option[str]` | first `?key=value` query pair, percent-decoded |
| `@body_bytes` | `() -> []u8` | the buffered request body |

The request body is always fully buffered by the time a handler sees it
(CORE scope, `[M-178-server-typed-body]`) — no streaming request bodies yet,
so there is no await/park point in reading it.

## `ServerResponse` constructors

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

| Constructor | Body / headers |
|---|---|
| `.text(status, s)` | `s`, `Content-Type: text/plain; charset=utf-8` |
| `.html(status, s)` | `s`, `Content-Type: text/html; charset=utf-8` |
| `.bytes(status, content_type, data)` | `data`, given `Content-Type` |
| `.empty(status)` | no body — `204`/`304`/… |
| `.redirect(status, location)` | no body, `Location: <location>` |
| `.json[T Serialize](status, v)` | `v` JSON-encoded, `Content-Type: application/json` (see [`Json[T]`](#intoresponse)) |
| `.stream(status, headers, producer)` / `.sse(producer)` | chunked/SSE body — see [serving.md](serving.md#streaming-and-sse) |

Every status-taking constructor also has a **deprecated** bare-`int`
overload (`ServerResponse.text(200, "ok")`) kept as a soft-migration bridge
over `unsafe { StatusCode.new_unchecked(status) }` — new code should use the
`StatusCode`-typed form (`StatusCode.OK`, or `StatusCode.new(code)` when the
value is dynamic — see [`StatusCode`](#statuscode) below).

Once built, a response is decorated fluently: `resp.header(name, value)`
(mutate-in-place, chainable), `resp.body(data)` (replace a fixed body),
`resp.status()`/`.status_code()` (typed / bare-`int` reads).

## `IntoResponse`

```nova
export type IntoResponse protocol {
    consume @into_response() -> ServerResponse
}
```

Everything a handler can return converges here — Axum's own `IntoResponse`
in spirit. Built-in conformers:

| Type | Becomes |
|---|---|
| `ServerResponse` | itself (identity) |
| `str` | `200 OK`, `text/plain` |
| `StatusCode` | bodyless response at that status |
| `Json[T Serialize]` | `200 OK`, `application/json` |
| any `T Serialize` (blanket) | `200 OK`, `application/json` — `Ok(user)` needs no `Json{}` wrapper |
| `HttpError` | mapped status + structured JSON error body — see [errors.md](errors.md) |
| `Result[R IntoResponse, E IntoResponse]` (blanket) | `Ok`/`Err`'s own `.into_response()` |

The `Result[R, E]` blanket is what gives `?`-ergonomics to a handler-adjacent
helper — write the fallible logic as a plain function returning
`Result[T, HttpError]`, then let `.into_response()` collapse it:

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

`json(v)` wraps a value as `Json[T]` for the response side (`json(user).into_response()`,
or `ServerResponse.json(status, v)` for a one-call typed-status JSON
response); `Json[T]` is the *same* type extracted from a request body — see
below.

## Typed extraction: `FromRequest`

```nova
export type FromRequest protocol {
    .from_request(req ServerRequest) -> Result[Self, HttpError]
}
```

Six built-in extractors implement it — each a one-field value wrapper with a
`@data()` accessor:

| Type | Source | Decoded via |
|---|---|---|
| `PathParam[T]` | matched `{name}` segments | serde, by field name |
| `Query[T]` | `?a=1&b=2` | serde, by field name |
| `Json[T]` | request body | serde JSON |
| `Bytes` | request body | none — raw `[]u8`, never fails |
| `Text` | request body | UTF-8 decode |
| `Headers` | request headers | none — the `HeaderMap`, never fails |

`PathParam[T]`/`Query[T]` reuse Nova's own `serde` as the deserialization
engine (`ParamsDeserializer`/`QueryDeserializer` — new `Deserializer`
*sources*, not a bespoke parser): **one** `PathParam[T]` extracts however
many `{name}` segments a route has, as fields of a record `T` matched by
name (`rename` field-attributes work the same as any other `#impl(Deserialize)`
type). The same applies to `Query[T]` for multi-key query strings.

**Today's canon** is calling `T.from_request(req)` manually, composed inside
a plain `Handler` — there is *no* sugar yet for a handler to take
`PathParam[T]`/`Query[T]`/`Json[T]` as bare fn parameters (Axum's
`async fn handler(Path(id): Path<u32>, Json(body): Json<T>)` shape). See
[roadmap.md](roadmap.md) for why, and what unblocks it.

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

Every extractor failure — a bad int in a path param, malformed JSON, a
missing field — is a typed `HttpError` (usually `400`), never a crash;
`e.into_response()` turns it into the same structured error body
[errors.md](errors.md) documents. An extractor's own doc-comment names the
exact failure it maps.

> **Note on naming.** `PathParam[T]` is a temporary name for what the design
> calls `Path[T]` — `Path` currently collides with `std.fs.Path` in some
> compile units (a compiler defect, tracked upstream); it will be renamed
> back to `Path[T]` once that is fixed. No behavior differs.

## `Bytes`/`Text`/`Headers`

The three extractors that never fail on well-formed input:

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

`Bytes.from_request` is infallible (`Result` only because the protocol
requires it — always `Ok`); `Text.from_request` can still fail on invalid
UTF-8.

## `multipart/form-data`

`Multipart` (RFC 7578, buffered — the whole body is already in memory by
228's body-limit design) parses fields *and* file uploads uniformly as
`Part`s:

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

`Multipart.@field(name)` returns the first part with that name;
`Multipart.@fields(name)` returns all of them (repeated fields — checkboxes,
multi-select); `Multipart.@file(name)` is the first part with that name
that *also* carries a `filename` (i.e. is an upload, not a plain field).

Every parse is bounded by `MultipartLimits` (256 parts / 8 MiB per part /
32 MiB total by default — `HttpError.body_too_large()` → `413` on any
excess, never an unbounded buffer grow); production servers thread their
own limits through `ServerPolicy` — see [serving.md](serving.md).

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

`StatusCode` is a value-newtype over `int`, range `100..599`. Frequent
values are named out-of-body constants (`StatusCode.OK`, `.CREATED`,
`.NO_CONTENT`, `.BAD_REQUEST`, `.NOT_FOUND`, `.METHOD_NOT_ALLOWED`,
`.TOO_MANY_REQUESTS`, `.INTERNAL_SERVER_ERROR`, …, `http` core's
`status.nv`); `StatusCode.new(code)` validates and returns
`Result[StatusCode, HttpError]` for a dynamic value; `unsafe { StatusCode.new_unchecked(code) }`
skips validation entirely (the escape hatch every bare-`int` constructor
overload is built on internally — prefer the validated forms in new code).

## Related documents

- [routing.md](routing.md) — where `Handler`s get registered
- [middleware.md](middleware.md) — wrapping a `Handler`
- [errors.md](errors.md) — `HttpError`'s own status/body mapping in full
- [roadmap.md](roadmap.md) — the extractor arity-overload sugar (planned)
- [`src/server.nv`](../src/server.nv), [`src/response.nv`](../src/response.nv), [`src/extract.nv`](../src/extract.nv), [`src/multipart.nv`](../src/multipart.nv)
