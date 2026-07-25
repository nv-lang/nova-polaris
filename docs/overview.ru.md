# Polaris — обзор

[English](overview.md) | **Русский**

Polaris — серверный веб-фреймворк для [Nova](https://nv-lang.org): `Router` на
основе сегмент-trie с шаблонами `{param}`/`{*rest}` и Axum-подобной
композицией методов, типизированные extractors (`FromRequest`), единая точка
схождения `IntoResponse` для возвращаемых значений хендлеров, chi-стиль
композиции middleware, набор готовых «батареек» (CORS, сжатие, логирование,
rate-limit), строительные блоки auth (Bearer/Basic/JWT/сессии), слой
WebSocket, отдача статических файлов и graceful accept-loop сервер
(`ServerPolicy`).

Если вы знакомы с [Axum](https://github.com/tokio-rs/axum) или
[FastAPI](https://fastapi.tiangolo.com/), многое покажется знакомым — Polaris
сознательно заимствует их формы там, где позволяет система типов и
effect-модель конкурентности Nova, и явный (типизированный `Result` вместо
паники, без скрытого `State<T>`-инжекта) там, где не позволяет.

## Отношение к `http`

Протокол на уровне провода — `Request`/`Response`/`HeaderMap`/`Url`/
`StatusCode`/`HttpError`, HTTP-**клиент** и сырой транспорт — живут в
отдельном пакете [`http`](https://github.com/nv-lang/nova-http) («ядро»).
Polaris от него зависит и пробрасывает его типы ошибок/статусов через
поверхность хендлеров; пользователь Polaris обычно не импортирует `http`
напрямую (он приходит транзитивно) — кроме случаев, когда нужно назвать
`StatusCode`/`HttpError` в сигнатуре собственного хендлера, как в примерах
ниже.

Axum стоит поверх `hyper` так же, как Polaris стоит поверх `http` — ядро
владеет байтами на проводе, Polaris — роутингом/хендлерами/middleware/serve.

## Минимальный сервер

```nova
test "overview: minimal handler, routed and served without a socket" {
    mut app = Router.new()
    app.get("/hello/{name}", fn(req ServerRequest) -> ServerResponse {
        ro name = req.param("name") ?? "world"
        ServerResponse.text(StatusCode.OK, "hello, ${name}")
    })!!

    ro wire = serve_once(app, get_req("/hello/nova"))
    assert(status_line(wire) == "HTTP/1.1 200 OK")
    assert(wire_str(wire).contains("hello, nova"))
}
```

`serve_once` — **чистый** драйвер запрос→ответ: сырые байты на входе, сырые
байты на выходе, без сокета вообще (собственная дисциплина `http` — D361
«mock-first»: весь конвейер routing/хендлер/middleware исчерпывающе
тестируем без единого открытого порта). Именно это делает тест выше — и
именно это прогоняет `nova test` для каждого примера этого набора доков —
см. [`src/doc_samples_test.nv`](../src/doc_samples_test.nv).

Реальный процесс вместо этого биндит `TcpListener` и вызывает
`polaris.serve.serve_router` (полная дока: [serving.md](serving.ru.md)):

```nova
fn overview_main() Net Time Detach -> () {
    mut app = Router.new()
    app.get("/hello/{name}", fn(req ServerRequest) -> ServerResponse {
        ro name = req.param("name") ?? "world"
        ServerResponse.text(StatusCode.OK, "hello, ${name}")
    })!!

    consume listener = TcpListener.bind(SocketAddr.from_str("0.0.0.0:8080")!!)!!
    serve_router(listener, app, ServerPolicy.new())
}
```

Эта функция проверяется компилятором (но не выполняется) собственной
`overview_main` из `doc_samples_test.nv` — ей нужен реальный сокет, поэтому
она не может жить внутри `test { }`-блока; что именно даёт `ServerPolicy`
(keep-alive, дедлайны, лимиты тела, admission control) поверх голого
эффект-ряда `Net`/`Time`/`Detach` — в [serving.md](serving.ru.md).

## Карта модулей

| Модуль | Что содержит |
|---|---|
| `polaris` (корень) | `Router`/`MethodRouter`, `ServerRequest`/`ServerResponse`, `Handler`, `Middleware`, `IntoResponse`/`Json[T]`, extractors (`PathParam[T]`/`Query[T]`/`Bytes`/`Text`/`Headers`/`Multipart`), auth (`Bearer`/`BasicAuth`/`JwtAuth`/сессии), `BackgroundTasks`, streaming/SSE, `WebSocketUpgrade`, чистые драйверы `serve_once`/`route_once` |
| `polaris.ws` | Протокольный слой WebSocket по RFC 6455: кодек фреймов, handshake, живой объект соединения `WebSocket` |
| `polaris.net` | `ServerPolicy` и живые примитивы accept-loop (`serve`, `serve_connection`, `handle_connection`), принимающие byte-level callback |
| `polaris.serve` | `serve_router`/`handle_connection_router` — обёртки над `polaris.net`, принимающие `Router` напрямую |
| `polaris.static` | Отдача статических файлов (`Static`-конфиг, `serve_path`, `static_handler`) |
| `polaris.middleware.cors` / `.compress` / `.log` / `.ratelimit` | Батарейки — каждая свой модуль, каждая построена на ядре `polaris.middleware(...)` |

Почему разделение на `polaris.net`/`polaris.serve` для проводного раннера:
слой провода (`polaris.net`, accept-loop, дедлайны, keep-alive) никогда не
импортирует `Router`/роутинг (нижний слой не зависит от верхнего) — вместо
этого он принимает голый callback `fn([]u8) -> ServerResponse`.
`polaris.serve.serve_router` — тонкая обёртка поверх него, которую
приложение вызывает на практике почти всегда. См. [serving.md](serving.ru.md).

## Содержание набора доков

- [routing.md](routing.ru.md) — `Router`, шаблоны путей, `MethodRouter`, вложенность, fallback'и
- [handlers-response.md](handlers-response.ru.md) — `ServerRequest`/`ServerResponse`, `IntoResponse`, extractors, `StatusCode`
- [middleware.md](middleware.ru.md) — написание и композиция `Middleware`
- [batteries.md](batteries.ru.md) — cors, compress, log, ratelimit
- [auth.md](auth.ru.md) — Bearer/Basic/JWT/куки/сессии
- [static-files.md](static-files.ru.md) — отдача встроенных/дисковых ассетов
- [websocket.md](websocket.ru.md) — слой апгрейда и протокола WebSocket
- [serving.md](serving.ru.md) — `ServerPolicy`, accept-loop, фоновые задачи
- [errors.md](errors.ru.md) — `HttpError`, маппинг статусов, `?`-эргономика
- [roadmap.md](roadmap.ru.md) — что запланировано, но ещё не реализовано

## Связанные документы

**Полный пример:** [`examples/01-hello`](../examples/01-hello) — этот же сервер, реально запущенный; полный набор — [`examples/README.ru.md`](../examples/README.ru.md), от простого к сложному.

- [`README.md`](../README.md) — питч пакета + установка
- [`src/doc_samples_test.nv`](../src/doc_samples_test.nv) — все примеры кода
  этого набора доков, компилируемые и прогоняемые `nova test`
- [nova-http](https://github.com/nv-lang/nova-http) — базовый пакет
  `Request`/`Response`/клиент/транспорт, от которого зависит Polaris
