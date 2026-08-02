# nova-polaris

**Polaris** ⭐ — серверный веб-фреймворк для [Nova](https://nv-lang.org):
`Router` на основе сегмент-trie (`{param}`/`{*rest}`, `nest`/fallback),
типизированные extractors, `IntoResponse`, композиция middleware +
батарейки (cors, compress, log, ratelimit), отдача статических файлов,
auth (Bearer/Basic/JWT/сессии), WebSocket и graceful accept-loop сервер.

**Nova** — новая звезда; **Polaris** — та, по которой держат курс.

```nova
import polaris.{Router, ServerRequest, ServerResponse}
import polaris.net.{ServerPolicy}
import polaris.serve.{serve_router}
import polaris.{StatusCode}
import std.net.{TcpListener, SocketAddr}

fn main() Net Time Detach -> () {
    mut app = Router.new()
    app.get("/hello/{name}", fn(req ServerRequest) -> ServerResponse {
        ro name = req.param("name") ?? "world"
        ServerResponse.text(StatusCode.OK, "hello, ${name}")
    })!!

    consume listener = TcpListener.bind("0.0.0.0:8080".to_socket_addr()!!)!!
    serve_router(listener, app, ServerPolicy.new())
}
```

Это ровно та форма, что компилируется (но не запускается — ей нужен
настоящий listener) как `overview_main` в
[`src/doc_samples_test.nv`](src/doc_samples_test.nv) — см.
[`docs/overview.ru.md`](docs/overview.ru.md) за тем же сервером,
прогоняемым без сокета через `serve_once`, и [`docs/serving.ru.md`](docs/serving.ru.md)
за тем, что даёт `ServerPolicy`.

Ядро протокола (типы `Request`/`Response`/`HeaderMap`/`Url`, HTTP-клиент,
транспорт) — пакет [`http`](https://github.com/nv-lang/nova-http): Polaris
от него зависит, и он приходит транзитивно для большинства пользователей
Polaris.

## Примеры

[`examples/`](examples/) — десять целых запускаемых приложений, от
простого к сложному, каждое свой пакет: `nova build --strict-effects` и
реально запусти. См. [`examples/README.ru.md`](examples/README.ru.md).

## Документация

- [`docs/overview.ru.md`](docs/overview.ru.md) — что такое Polaris,
  разбор минимального сервера выше, карта модулей
- [`docs/routing.ru.md`](docs/routing.ru.md) — `Router`, шаблоны путей,
  `MethodRouter`, `nest`, fallback'и
- [`docs/handlers-response.ru.md`](docs/handlers-response.ru.md) —
  `ServerRequest`/`ServerResponse`, `IntoResponse`, типизированные
  extractors, `StatusCode`
- [`docs/extractors.ru.md`](docs/extractors.ru.md) — семейство
  `FromRequest`, typed-маршруты (`TypedRoute`/`*_typed`/`*_typed_h`), связь
  с OpenAPI
- [`docs/middleware.ru.md`](docs/middleware.ru.md) — написание и
  композиция `Middleware`
- [`docs/batteries.ru.md`](docs/batteries.ru.md) — cors, compress, log,
  ratelimit
- [`docs/auth.ru.md`](docs/auth.ru.md) — Bearer/Basic/JWT/куки/сессии
- [`docs/static-files.ru.md`](docs/static-files.ru.md) — отдача
  встроенных/дисковых ассетов
- [`docs/websocket.ru.md`](docs/websocket.ru.md) — слой апгрейда и
  протокола WebSocket
- [`docs/serving.ru.md`](docs/serving.ru.md) — `ServerPolicy`,
  accept-loop, фоновые задачи
- [`docs/errors.ru.md`](docs/errors.ru.md) — `HttpError`, маппинг
  статусов, `?`-эргономика
- [`docs/roadmap.ru.md`](docs/roadmap.ru.md) — что запланировано, но ещё
  не реализовано

Каждый пример кода в этом наборе документации компилируется и
выполняется как часть [`src/doc_samples_test.nv`](src/doc_samples_test.nv)
— `nova test src/doc_samples_test.nv` и есть собственный гейт
корректности доки.

[English version of this README](README.md).

## Статус

Слои фреймворка (`Router`, extractors, middleware, auth, WebSocket,
статика, serve) извлечены из `nova-http` в этот пакет (план 222);
`nova-http` теперь содержит только ядро протокола. Актуальную,
сверенную с кодом поверхность — см. доки выше, а что ещё впереди — в
[`docs/roadmap.ru.md`](docs/roadmap.ru.md).

## Лицензия

MIT OR Apache-2.0.
