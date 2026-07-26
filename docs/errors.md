# Errors

**English** | [Русский](errors.ru.md)

`HttpError` is the single structural error type for the whole `http`/Polaris
stack (client and server alike) — every fallible operation returns
`Result[T, HttpError]`. This page covers it through the server's own lens:
how a value handlers build/receive turns into a wire response.

Source: `HttpError`/`ErrorKind` — [nova-http](https://github.com/nv-lang/nova-http)'s
`src/error.nv`; the server-side mapping — [`src/response.nv`](../src/response.nv).

---

## Contents

- [`HttpError` → `ServerResponse`](#httperror--serverresponse)
- [Status mapping](#status-mapping)
- [Attaching context: `@with_url`](#attaching-context-with_url)
- [`?`-ergonomics via the `Result` blanket](#-ergonomics-via-the-result-blanket)
- [Panics vs `Fail`: which one for what](#panics-vs-fail-which-one-for-what)
- [Related documents](#related-documents)

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

`HttpError`'s `#impl(IntoResponse)` (see [handlers-response.md](handlers-response.md#intoresponse))
maps it to a status **and** a structured JSON body — FastAPI-class shape,
not bare text:

```json
{"error": "<kind-name>", "message": "<HttpError.to_str()>"}
```

`<kind-name>` is a short lowercase tag (`"protocol"`, `"invalid_url"`,
`"body_too_large"`, `"blocked"`, `"other"`, …) — stable, matchable, and
distinct from `message`, which is the free-text human description (log-
oriented — never assume its exact wording).

## Status mapping

| `ErrorKind` | Status |
|---|---|
| `Connect`, `Dns`, `Tls`, `Timeout`, `Closed`, `Canceled` | `503 Service Unavailable` |
| `Protocol(_)`, `InvalidUrl`, `InvalidHeader` | `400 Bad Request` |
| `Status(c)` | echoes `c` verbatim |
| `TooManyRedirects(_)`, `Other(_)` | `500 Internal Server Error` |
| `BodyTooLarge` | `413 Payload Too Large` |
| `Blocked(_)` | `403 Forbidden` |

Most of the transport-class kinds (`Connect`/`Dns`/`Tls`/`Timeout`/…) come
from `http`'s **client** side (`HttpClient` calls another service and that
call fails) — a Polaris handler proxying such a call and returning the
resulting `HttpError` gets a sensible `503` for free, no manual mapping
needed. `ErrorKind` is **open** (`Other(str)` is the catch-all) — a `match`
over it must always carry a wildcard arm, so adding a new kind later is
non-breaking.

## Attaching context: `@with_url`

`e.with_url(u)` (from `http` core) attaches a `Url` to an error for
richer logs/diagnostics at a client-call boundary — it does not change the
status mapping above; it is metadata only, read via `HttpError.url`.

## `?`-ergonomics via the `Result` blanket

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

Because `HttpError` (and `str`, and any `T Serialize`) implements
`IntoResponse`, the blanket `Result[R IntoResponse, E IntoResponse] : IntoResponse`
means a plain helper function returning `Result[T, HttpError]` — written
with ordinary `?`-propagation internally, no `ServerResponse` in sight —
slots straight into a handler with one `.into_response()` call at the
boundary. This is the idiomatic shape for request-handling logic in
Polaris: keep your domain functions returning `Result[T, HttpError]`, keep
`ServerResponse`-building at the very edge.

## Panics vs `Fail`: which one for what

Two different failure channels reach a handler, and Polaris treats them
differently on purpose (222.20 Ф.3 Волна C):

- **Expected, recoverable outcomes** (not-found, bad input, unauthorized,
  upstream 503, …) are **`Result[T, HttpError]`** — see the `?`-blanket
  above. This is the default channel for anything your handler's own logic
  anticipates.
- **Programmer errors and truly unexpected failures** (an assertion, an
  out-of-bounds index, an unhandled `Fail`-effect throw escaping the
  handler body) are **panics/escaped throws** — Polaris does *not* ask you
  to wrap every possible defect in a `Result`. Per-request `Stop`-supervision
  (D416) catches these at the connection boundary:

```nova
ro app = build_router()
// ServerPolicy.panic_response(): InternalError500 (default) writes a
// generic 500 and keeps the connection alive for the NEXT request on it;
// Close drops the connection with no response body instead.
serve_router(listener, app, ServerPolicy.new())
```

  The caught panic/throw is logged once via the ambient `Log` effect
  (`"handler panic: <message>"`) and answered per `ServerPolicy.
  panic_response()` — `InternalError500` (the default) or `Close`. **Message-
  only, by design** (D437): the runtime's full "message + throw-site +
  propagation trace" diagnostic is only ever printed by the top-level
  unhandled-abort path — there is no Nova-level accessor that hands a trace
  to a `Supervisor` handler, so recover-500 logs honestly what it actually
  has (the message via `err.try_as[str]()`), not a fabricated "site".

**Rule of thumb:** if your own code can name the failure mode ahead of
time, return it as `Result[T, HttpError]`. If it can't — a genuine bug, an
invariant violation, a dependency panicking — let it panic; recover-500
contains the blast radius to one request, the process (and every other
in-flight connection) keeps running.

## Related documents

**Full example:** [`examples/03-json-api`](../examples/03-json-api) — `HttpError`/`StatusCode` and the `Result[T, HttpError]` blanket, running for real.

- [handlers-response.md](handlers-response.md) — `IntoResponse` in full, extractor failure modes
- [auth.md](auth.md) — `401`s from Bearer/Basic/JWT extractors, same mapping
- `HttpError`/`ErrorKind` themselves — [nova-http](https://github.com/nv-lang/nova-http)'s own `src/error.nv`
- [`src/response.nv`](../src/response.nv), [`src/response_test.nv`](../src/response_test.nv)
