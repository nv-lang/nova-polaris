# Roadmap

**English** | [Русский](roadmap.ru.md)

Everything on this page is **planned, not implemented** — no code here has
run against a compiler. If a feature below sounds like it should already
work, it doesn't yet; check the corresponding doc page for what today's
actual canon is instead.

---

## Contents

- [Extractor arity-overload sugar](#extractor-arity-overload-sugar)
- [`Path[T]` rename](#patht-rename)
- [OpenAPI generation](#openapi-generation)
- [Phase B: module split](#phase-b-module-split)
- [Request validation](#request-validation)
- [Sessions: generic store](#sessions-generic-store)
- [Background-task graceful shutdown](#background-task-graceful-shutdown)
- [Related documents](#related-documents)

---

## Extractor arity-overload sugar

Today (see [handlers-response.md](handlers-response.md#typed-extraction-fromrequest)),
using a typed extractor means calling `T.from_request(req)` by hand inside a
plain `Handler`:

```nova
r.get("/users/{id}", fn(req ServerRequest) -> ServerResponse {
    match PathParam[UserId].from_request(req) {
        Ok(p)  => /* ... */
        Err(e) => e.into_response()
    }
})!!
```

The design calls for `Router.@get`/`@post`/`@put`/`@delete`/`@patch` to gain
0–4-extractor overloads so a handler can take extractors as bare function
parameters instead (Axum's own shape):

```nova
// PLANNED — not implemented, do not copy this into real code yet.
export fn Router mut @get[T1 FromRequest, R IntoResponse](path str, h fn(T1) -> R) -> Result[Router, HttpError]
```

**Why it isn't implemented yet**: the smallest possible version of this
sugar — one new bound-generic overload on `Router.@get`, with *zero* call
sites anywhere — already breaks codegen on the pre-existing, unrelated,
non-generic `@get(path, Handler)` call sites already in this package's own
test suite (a checker/codegen arity-overload mismatch, tracked upstream in
the nova compiler, not something this package can work around locally).
The low-level `Router.@get(path, Handler)` + manual per-extractor
composition shown throughout this doc set remains the only registration
path until that compiler gap closes.

## `Path[T]` rename

`PathParam[T]` ([handlers-response.md](handlers-response.md#typed-extraction-fromrequest))
is a temporary name. The design's canonical name is `Path[T]` (Axum parity)
— renamed to `PathParam[T]` only because `Path` currently collides with
`std.fs.Path` inside some compile units (a same-name cross-module
typecheck-bleed defect, tracked upstream). Once that closes, `PathParam[T]`
becomes `Path[T]` and `PathParam[T]` goes away — a rename, not a new type,
and not a behavior change.

## OpenAPI generation

Not implemented. No `#[derive(OpenApi)]`/`utoipa`-equivalent exists yet —
route/extractor/response shapes are not currently reflected into a spec
document. If and when this lands, it will be documented here first, with a
worked example, exactly like everything else in this doc set — no
speculative surface is described in the meantime.

## Phase B: module split

The package's `src/` root currently holds most of the framework as
co-equal "root peer" files (`server.nv`, `response.nv`, `extract.nv`,
`middleware.nv`, `auth.nv`, `multipart.nv`, `background.nv`, `ws_upgrade.nv`,
…) all in `module polaris` — a consequence of the extraction out of
`nova-http` landing in one wave, not a permanent shape. A follow-up pass is
expected to carve these into proper sub-modules (mirroring the
`polaris.ws`/`polaris.net`/`polaris.static`/`polaris.middleware.*` split
that already exists) — a reorganization, not an API change; this doc set
will move its own source-file links accordingly when it happens.

## Request validation

No dedicated validation layer exists yet beyond what `serde`'s own
deserialization already rejects (a wrong type, a missing required field).
FastAPI-style declarative constraints (min/max length, numeric ranges,
regex, cross-field checks) are not implemented. Until this lands, validate
by hand at the top of a handler (or inside a `Result`-returning helper —
see [errors.md](errors.md#-ergonomics-via-the-result-blanket)) and return a
typed `HttpError` on failure.

## Sessions: generic store

[`auth.md`](auth.md#sessions) documents the current sessions **skeleton**:
one concrete `MemorySessionStore` behind the `SessionStore` protocol. A
generic `session_layer[S SessionStore](store S, ...)` — so `session_layer`
itself doesn't hardcode the in-memory implementation — is the natural
follow-up, deferred until generic-capture codegen (a closure capturing a
generic-typed value across the M:N fiber boundary) is proven safe for this
shape.

## Background-task graceful shutdown

[`serving.md`](serving.md#background-tasks) documents `BackgroundTasks.@drain()`
as it exists today: called synchronously by the connection driver after a
successful write, with **no** lifecycle tie-in to server shutdown, because
there is no accept-loop-wide graceful-shutdown deadline-drain in this
package yet. Two shapes are under consideration once one lands: wrapping
`@drain()` in a `supervised(deadline:)` at the run-loop level (simple, but
silently drops tasks that hadn't started by the deadline), or a process-wide
in-flight counter the shutdown path waits on with the same deadline
(symmetric to FastAPI/Starlette's own lifespan-shutdown, doesn't lose
already-started work). Neither is implemented.

## Related documents

- [handlers-response.md](handlers-response.md) — today's extractor canon
- [auth.md](auth.md) — today's sessions skeleton
- [serving.md](serving.md) — today's `BackgroundTasks`/`ServerPolicy`
- [errors.md](errors.md) — today's error-handling canon
