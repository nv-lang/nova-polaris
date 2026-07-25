# Polaris documentation

Start here: **[overview.md](overview.md)** — what Polaris is, a minimal server, the module map.

| Section | Covers |
|---|---|
| [overview.md](overview.md) | Polaris in one page; relation to the `http` core package |
| [routing.md](routing.md) | `Router`, path patterns `{name}`/`{*rest}`, `MethodRouter`, `nest`, fallbacks |
| [handlers-response.md](handlers-response.md) | `ServerRequest`/`ServerResponse`, `IntoResponse`, typed extractors, `StatusCode` |
| [middleware.md](middleware.md) | writing and composing `Middleware`, layer ordering |
| [batteries.md](batteries.md) | cors, compress, log, ratelimit |
| [auth.md](auth.md) | Basic/Bearer/JWT, cookies, sessions |
| [static-files.md](static-files.md) | serving embedded/on-disk assets |
| [websocket.md](websocket.md) | WebSocket upgrade + protocol layer |
| [serving.md](serving.md) | `ServerPolicy`, accept loop, background tasks, graceful |
| [errors.md](errors.md) | `HttpError`, status mapping, `?`-ergonomics |
| [roadmap.md](roadmap.md) | planned, not implemented yet |

Every code sample compiles as part of [`../src/doc_samples_test.nv`](../src/doc_samples_test.nv).

**Русская версия:** [README.ru.md](README.ru.md) · each section has a `.ru.md` sibling.
