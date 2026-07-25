# Документация Polaris

Начните отсюда: **[overview.ru.md](overview.ru.md)** — что такое Polaris, минимальный сервер, карта модулей.

| Раздел | О чём |
|---|---|
| [overview.ru.md](overview.ru.md) | Polaris на одной странице; связь с пакетом-ядром `http` |
| [routing.ru.md](routing.ru.md) | `Router`, шаблоны пути `{name}`/`{*rest}`, `MethodRouter`, `nest`, fallback'и |
| [handlers-response.ru.md](handlers-response.ru.md) | `ServerRequest`/`ServerResponse`, `IntoResponse`, типизированные экстракторы, `StatusCode` |
| [middleware.ru.md](middleware.ru.md) | написание и композиция `Middleware`, порядок слоёв |
| [batteries.ru.md](batteries.ru.md) | cors, compress, log, ratelimit |
| [auth.ru.md](auth.ru.md) | Basic/Bearer/JWT, cookies, сессии |
| [static-files.ru.md](static-files.ru.md) | отдача встроенных/дисковых файлов |
| [websocket.ru.md](websocket.ru.md) | WebSocket-upgrade + протокольный слой |
| [serving.ru.md](serving.ru.md) | `ServerPolicy`, accept-цикл, фоновые задачи, graceful |
| [errors.ru.md](errors.ru.md) | `HttpError`, маппинг статусов, эргономика `?` |
| [roadmap.ru.md](roadmap.ru.md) | запланировано, ещё не реализовано |

Каждый пример кода компилируется в составе [`../src/doc_samples_test.nv`](../src/doc_samples_test.nv).

**English version:** [README.md](README.md) · у каждого раздела есть англ. пара без `.ru`.
