# 06 — static-site

Embedded static assets (`EmbeddedDir`, bytes baked into the binary), index-
file resolution at the root, per-response `Cache-Control`, and content
ETags.

By way of: axum's `static-file-server` example.

## Run

```sh
nova build --strict-effects src/main.nv
./main   # binds 0.0.0.0:18087
```

```sh
curl http://localhost:18087/                       # index.html content
curl -D - http://localhost:18087/assets/style.css   # 200, ETag, Cache-Control, content-type: text/css
curl http://localhost:18087/assets/notes/hello.txt  # a nested asset
curl -o /dev/null -w '%{http_code}\n' http://localhost:18087/assets/missing.txt   # 404
```

## What to poke at

- Add an `If-None-Match` header with the `ETag` you got back — a `304` with
  no body, per [`docs/static-files.md`](../../docs/static-files.md).
- Add a `Range: bytes=0-4` header on `/assets/style.css` — a `206` with
  `Content-Range`.
- Swap `EmbeddedDir` for `DirFs` (a real directory under the `Fs` effect,
  useful for dev live-reload) — see the module doc-comment on
  [`src/static.nv`](../../src/static.nv).

## A gap this example works around

`polaris.static.static_handler(fs, cfg, param)` — the one-call ready-`Handler`
helper `docs/static-files.md` documents — currently hits a codegen gap for
this package's own `EmbeddedDir` (`nova: out of memory` on the very first
served asset, isolated during this wave). `/assets/{*path}` here calls
`serve_path` directly from a plain closure instead — the exact same shape
the `/` route already uses, and exactly what `static_handler` does
internally (see its one-line body in `src/static.nv`) — unaffected by the
gap. Filed upstream.

## Related documentation

- [`docs/static-files.md`](../../docs/static-files.md) — `EmbeddedDir`, ETag/Range/index rules, safety

[Русский](README.ru.md) · see [`examples/README.md`](../README.md) for why `main()`/`production_main()` come in a pair.
