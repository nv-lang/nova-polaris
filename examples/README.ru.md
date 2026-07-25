# Примеры Polaris

Десять рабочих приложений — от простого к сложному, каждое в своём
самостоятельном пакете с зависимостью на `polaris` (и `http` — ради
`StatusCode`/`HttpError`) по локальному пути. Каждый пример собирается
`--strict-effects` и реально запускается: старт → `curl` → останов — см.
[`run_smokes.ps1`](run_smokes.ps1) / [`run_smokes.sh`](run_smokes.sh).

Дока ([`../docs/`](../docs/)) показывает один приём на сниппет; эти примеры —
как приёмы складываются в цельную маленькую программу, которую можно взять
за стартовую точку.

| # | Пример | Показывает | По мотивам |
|---|---|---|---|
| [01](01-hello/) | `hello` | `Router.new` + один `get` + serve | axum `hello-world`, Express hello |
| [02](02-routing/) | `routing` | `{name}`/`{*rest}`, `MethodRouter`, `nest`, fallback-404, конфликты путей | axum routing example, chi routing |
| [03](03-json-api/) | `json-api` | REST CRUD (todo в памяти): `req.json[T]`, `ServerResponse.json`, `#impl(Serialize/Deserialize)` | axum `todos`, туториал FastAPI |
| [04](04-middleware/) | `middleware` | свой `middleware(fn(req, next))`, `@then`, порядок layers, log+ratelimit | axum tower-middleware showcase, цепочка middleware Express |
| [05](05-auth/) | `auth` | Basic + Bearer/JWT, session-cookie, публичная/приватная зона через `nest`+`layer` | axum `jwt`, туториал FastAPI OAuth2 |
| [06](06-static-site/) | `static-site` | `polaris.static` + fallback на index, кеш-заголовки | axum `static-file-server` |
| [07](07-sse-stream/) | `sse-stream` | `StreamBody` + `sse_event`: живой тикер | axum `sse` |
| [08](08-websocket-echo/) | `websocket-echo` | `WebSocketUpgrade`, `WebSocket.with_limit`, echo-цикл | axum `websockets` |
| [09](09-graceful/) | `graceful` | `ServerPolicy` (лимиты/admission), `BackgroundTasks`, recover-500 | axum `graceful-shutdown` + `key-value-store` |
| [10](10-mini-service/) | `mini-service` | json-api + auth + стек middleware + static + policy — всё вместе | RealWorld (Conduit) — урезанный профиль |

## Собрать один пример

```sh
cd 01-hello
nova build --strict-effects src/main.nv
./main
```

В README каждого примера — свой порт и пара `curl`-запросов на пробу.

## Почему у каждого `main()` одна и та же форма

В `src/main.nv` каждого примера — **две** функции с формой точки входа:

- **`main()`** — то, что реально запускается. Она сама крутит цикл
  `TcpListener.accept()`, разбирая каждое соединение через низкоуровневый
  `polaris.serve.handle_connection_router` (в
  [`../docs/serving.md`](../docs/serving.md) он описан как строительный
  блок для одного запроса, из которого сделан `serve_router`), внутри
  одного блока `supervised { spawn { ... } }` — accept прямо на
  bootstrap-файбере паркуется невалидно (`nova_sched_park: invalid
  scope/slot`), так что циклу accept нужен свой спавненный файбер вне
  зависимости от того, каким драйвером соединение обслуживается дальше.
- **`production_main()`** — компилируется, но **никогда не вызывается**
  (та же конвенция «compile-only», что и в `docs/doc_samples_test.nv` для
  всего, что требует реального сокета). Она показывает *канонический* вид,
  которому учит каждая страница доки: bind, затем один вызов
  `polaris.serve.serve_router(listener, router, ServerPolicy.new())` — полный
  accept-цикл с keep-alive, дедлайнами, лимитами тела и admission control.
  На этом снимке тулчейна этот вызов не линкуется
  (`undefined symbol: nova_fn_hook`) — минимальный `detach`/`spawn`-репро в
  этой волне локализовал причину до hook'а recover-500-восстановления после
  паники, который `serve_router` устанавливает на супервизию каждого
  запроса, — не до чего-либо в собственном коде роутинга/хендлеров/
  middleware Polaris, и hook вообще не задействован при работе через
  низкоуровневый `handle_connection_router` выше. Заведено на дальнейшую
  доводку рантайм-hook'ов; в остальном каждый пример реально исполняет код
  фреймворка (`Router`, экстракторы, middleware, auth, статика, SSE,
  WebSocket) по-настоящему, по реальному сокету, отвечая на реальные
  `curl`-запросы.

## Порты

Каждый пример слушает свой нестандартный порт (`18081 + NN`), чтобы
`run_smokes` мог собрать и прогнать все примеры без коллизий:

| Пример | Порт |
|---|---|
| 01-hello | 18082 |
| 02-routing | 18083 |
| 03-json-api | 18084 |
| 04-middleware | 18085 |
| 05-auth | 18086 |
| 06-static-site | 18087 |
| 07-sse-stream | 18088 |
| 08-websocket-echo | 18089 |
| 09-graceful | 18090 |
| 10-mini-service | 18091 |

[English](README.md)
