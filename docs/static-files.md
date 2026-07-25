# Static file serving

**English** | [Русский](static-files.ru.md)

`polaris.static` serves files from a [`ReadFs`](https://github.com/nv-lang/nova/blob/main/std/src/fs/readfs.nv)
source — `EmbeddedDir` (bytes baked into the binary, deterministic, the
usual production choice) or `DirFs` (live filesystem reads under the `Fs`
effect, useful for dev live-reload). Semantics follow Go's
`http.FileServer`/`serveContent` for the ETag/Range corners, and
tower-http's `ServeDir` for the overall shape.

Source: [`src/static.nv`](../src/static.nv).

---

## Contents

- [Serving embedded assets](#serving-embedded-assets)
- [What's implemented](#whats-implemented)
- [Safety](#safety)
- [Related documents](#related-documents)

---

## Serving embedded assets

```nova
fn static_fixture() -> EmbeddedDir =>
    EmbeddedDir.new([
        EmbeddedEntry { path: "index.html", data: "<h1>hi</h1>".bytes() },
        EmbeddedEntry { path: "notes/readme.txt", data: "hello world".bytes() },
    ])

test "static-files: serve embedded assets — mime, ETag, index resolution, 404" {
    mut r = Router.new()
    r.get("/assets/{*path}", static_handler(static_fixture(), Static.new(), "path"))!!

    ro txt = route_once(r, get_req("/assets/notes/readme.txt"))
    assert(txt.status_code() == 200)
    assert(hdr(txt, "content-type") == "text/plain; charset=utf-8")
    assert(hdr(txt, "etag") != "")

    ro missing = route_once(r, get_req("/assets/nope.txt"))
    assert(missing.status_code() == 404)

    // empty {*path} can't come through the router (no request maps to it) —
    // call serve_path directly to serve the index file, same as static_handler does.
    mut r2 = Router.new()
    r2.get("/", fn(req ServerRequest) -> ServerResponse =>
        serve_path(static_fixture(), Static.new(), "", req))!!
    ro idx = route_once(r2, get_req("/"))
    assert(hdr(idx, "content-type") == "text/html; charset=utf-8")
}
```

`EmbeddedDir`/`EmbeddedEntry` are prelude types (`embed_dir("dir")` at
build time is the usual way to populate one from a real directory — see
`std/src/prelude/embed.nv`); entries must be sorted by path. `static_handler(fs, cfg, param)`
builds a ready `Handler` for a `{*param}` catch-all route in one call;
`serve_path(fs, cfg, path, req)` is the lower-level function it wraps, for
wiring a static handler by hand (e.g. under `/` where no `{*path}` capture
is available, as the index case above shows).

`Static.new()` defaults to `index.html` for `""`/trailing-`/` paths and no
`Cache-Control` header; `@index(name)`/`@cache_control(v)` override either.

## What's implemented

A practical subset of Go's `serveContent`, adapted to a `ReadFs` that
carries no mtime:

| Feature | Behavior |
|---|---|
| Content-derived ETag | strong tag, `"<len-hex>-<crc32-hex>"` — identical bytes get an identical tag on every host, unlike an mtime-derived one |
| `If-None-Match` | `304`, list/`W/`-prefix/`*` all honored (weak comparison — fine for a content ETag) |
| `Range` (single) | `206` with `Content-Range`; `If-Range` guards it against a stale validator (full `200` on mismatch) |
| Unsatisfiable range | `416` + `Content-Range: bytes */<size>` |
| Malformed/multi-range | ignored → full `200` (Go's own rule) |
| MIME | by extension, small built-in table (html/css/js/json/svg/images/fonts/wasm/pdf/xml/mp4/…, else `application/octet-stream`) |
| Index resolution | `""`/trailing-`/` → `<cfg.index>` |

**Not implemented**: `If-Modified-Since`/`Last-Modified` (no mtime to
compare against — the ETag subsumes it), multi-range/multipart responses
(Go serves these; rare, deferred), and an automatic `HEAD` answer (method
routing is `Router`'s job — register `HEAD` explicitly if you need it).

## Safety

A `..`-escape attempt never reaches user code: `DirFs` rejects it
internally (a boundary check inside the filesystem abstraction) and
`EmbeddedDir` is an exact-key map where a `../`-containing key simply does
not exist — both arrive at a plain `404`, indistinguishable from any other
missing path (no information leak about *why* a path was rejected).

## Related documents

- [routing.md](routing.md) — the `{*path}` catch-all pattern `static_handler` expects
- [handlers-response.md](handlers-response.md) — `ServerResponse`, headers
- [`src/static.nv`](../src/static.nv), [`src/static_test.nv`](../src/static_test.nv)
