# Serve: `ServerPolicy`, accept-loop, фоновые задачи

[English](serving.md) | **Русский**

Эта страница про то, что происходит **вокруг** `Router`, когда он уже есть:
биндинг сокета и accept-loop, ручки, делающие этот цикл
production-пригодным (keep-alive, дедлайны, лимиты тела, admission
control), streaming/SSE-ответы и отложенная работа в духе FastAPI'шного
`BackgroundTasks`.

Исходник: [`src/net/serve.nv`](../src/net/serve.nv),
[`src/net/config.nv`](../src/net/config.nv), [`src/net/servernet.nv`](../src/net/servernet.nv),
[`src/serve/serve.nv`](../src/serve/serve.nv), [`src/background.nv`](../src/background.nv).

---

## Содержание

- [Слои: `polaris.net` vs `polaris.serve`](#слои-polarisnet-vs-polarisserve)
- [`ServerPolicy`](#serverpolicy)
- [Запуск accept-loop](#запуск-accept-loop)
- [Streaming и SSE](#streaming-и-sse)
- [Фоновые задачи](#фоновые-задачи)
- [Связанные документы](#связанные-документы)

---

## Слои: `polaris.net` vs `polaris.serve`

Слой провода (`polaris.net` — accept-loop, keep-alive, дедлайны, лимит
размера тела, chunked-декод) **никогда** не импортирует `Router`/роутинг
(нижний слой не зависит от верхнего) — `serve`/`serve_connection`/
`handle_connection` там принимают голый byte-level callback
`fn([]u8) -> ServerResponse`. `polaris.serve.serve_router`/
`.handle_connection_router` — тонкие обёртки, принимающие `Router`
напрямую, которые почти любое приложение вызывает на практике — те же, что
используются повсюду в этом наборе доков.

## `ServerPolicy`

```nova
test "serving: ServerPolicy documented defaults + fluent tuning" {
    ro p = ServerPolicy.new()
    assert(p.max_inflight() == 16)
    assert(p.reject_with_503() == true)
    assert(p.max_requests_per_conn() == 100)
    assert(p.max_body_bytes() == 1048576)

    mut q = ServerPolicy.new()
    q.max_inflight(64).max_body_bytes(4 * 1024 * 1024)
    assert(q.max_inflight() == 64)
    assert(q.max_body_bytes() == 4194304)
}
```

Каждая ручка accept-loop/соединения живёт на одном fluent value-record:

| Ручка | По умолчанию | Значение |
|---|---|---|
| `max_inflight` | 16 | сколько соединений обрабатывается одновременно, прежде чем admission начнёт отклонять |
| `reject_with_503` | `true` | сверх-лимитный accept получает настоящий `503` (вместо голого close) |
| `max_requests_per_conn` | 100 | сколько запросов обслуживается на одном keep-alive соединении, прежде чем принудительный `Connection: close` |
| `header_deadline` / `read_deadline` | 5с / 5с | защита от slowloris — блок заголовков / чтение тела, у каждого своё окно |
| `idle_deadline` | 60с | как долго открытое keep-alive соединение может простаивать |
| `max_body_bytes` | 1 МиБ | лимит тела запроса — превышение это `413`, никогда неограниченный рост буфера |
| `max_multipart_parts`/`_part_size`/`_total_bytes` | 256 / 8 МиБ / 32 МиБ | прокидывается в `Multipart.from_request`, см. [handlers-response.md](handlers-response.ru.md#multipartform-data) |
| `panic_response` | `InternalError500` | чем отвечает пойманная паника хендлера |

У каждого поля есть геттер `@x()` и fluent-сеттер `mut @x(v) -> @` —
сцепляйте несколько на одной `mut`-переменной, как делает `q` выше.

## Запуск accept-loop

```nova
fn serving_main(consume listener TcpListener, consume single TcpStream, app Router) Net Time Detach -> () {
    serve_router(listener, app, ServerPolicy.new())
    ro _ = handle_connection_router(single, app)
}
```

- **`serve_router(listener, router, policy)`** — переиспользуемый
  accept-loop: биндим один раз, `detach`-аем fiber на каждое принятое
  соединение (bounded-конкурентно, не последовательно; admission-gate по
  `max_inflight` через `Semaphore`), каждое соединение циклически читает
  governed-запросы (дедлайны/лимит тела/chunked-декод из `ServerPolicy`
  уже применены) и обслуживает их keep-alive. Временная ошибка `accept()`
  ненадолго откатывается назад и продолжает цикл, вместо того чтобы
  положить весь сервер; сверх-лимитный accept опционально отвечает
  настоящим `503` (`policy.reject_with_503()`). Нужны `Net`, `Time` (для
  дедлайнов) и `Detach` (спавнит orphan-фиберы на соединение).
- **`handle_connection_router(stream, router)`** — одноразово,
  `Connection: close`, один запрос на уже принятое соединение. Без
  keep-alive/дедлайнов/policy — низкоуровневый строительный блок, из
  которого построен `serve_router`; полезен, когда accept-loop уже ведёте
  сами (тестовый harness, встраивающий хост).

Пойманная паника хендлера отвечается согласно `policy.panic_response()`
(по умолчанию `InternalError500` — честный `500`, соединение остаётся
живым для *следующего* запроса, если обе стороны договорились о
keep-alive) и логируется через `policy.panic_emit`/`@panic_sink(f)`
(по умолчанию stdout, перенаправляемо — тот же рецепт, что у `@sink`
из `Log`, [batteries.md](batteries.ru.md#log)).

См. [`overview.md`](overview.ru.md#минимальный-сервер) для минимального
end-to-end `main()`, который сокращённо описывает doc-comment этой функции.

## Streaming и SSE

```nova
test "serving: SSE — text/event-stream headers + event/data framing" {
    mut r = Router.new()
    r.get("/events", fn(req ServerRequest) -> ServerResponse {
        ro chunks [][]u8 = [sse_event("tick", "1"), sse_event("done", "bye")]
        ServerResponse.sse(StreamBody.from_chunks(chunks))
    })!!
    ro wire = serve_once(r, get_req("/events"))
    ro s = wire_str(wire)
    assert(s.contains("content-type: text/event-stream"))
    assert(s.contains("event: tick\ndata: 1\n\n"))
    assert(s.ends_with("0\r\n\r\n"))
}
```

`ServerResponse.stream(status, headers, producer)` строит ответ
`Transfer-Encoding: chunked` для любого тела, чья итоговая длина заранее
не известна; `.sse(producer)` — специализация `text/event-stream`
(проставляет стандартные no-cache заголовки). `StreamBody` — pull-источник
— `stream_body(f)` оборачивает замыкание, возвращающее `Option[[]u8]`
(`None` = конец потока; тело может заблокировать вызывающий fiber,
например цикл `ChanReader.recv()`, что под M:N-рантаймом паркует только
fiber этого соединения, не весь event loop); `StreamBody.from_chunks(list)`
(использовано выше) — удобная форма поверх заранее собранного конечного
списка chunk'ов. `sse_event(event, data)` форматирует одно SSE-событие на
проводе.

Живой сокет-писатель отправляет каждый chunk своим собственным `write_all`
— настоящая инкрементальная доставка, с write-backpressure, идущим
бесплатно из уже существующего поведения `Net.write` (park при полном
буфере) — без специального механизма контроля потока. `serve_once`
(использован в тесте выше, и повсюду в этом наборе доков) вместо этого
полностью **осушает** продюсер в один буфер — итоговые байты на проводе
байт-в-байт идентичны тому, что получает живой клиент, просто
материализованы заранее, а не проталкиваются инкрементально — именно это
и делает функцию пригодной для теста без сокета.

## Фоновые задачи

```nova
test "serving: BackgroundTasks run AFTER the response, in FIFO order" {
    mut order []int = []
    mut bg = BackgroundTasks.new()
    bg.add(|| { order.push(1) })
    bg.add(|| { order.push(2) })
    assert(bg.task_count() == 2)
    bg.drain() // the connection driver calls this once the response bytes are on the wire
    assert(order.len() == 2)
    assert(order[0] == 1)
    assert(order[1] == 2)
}
```

Аналог FastAPI'шного `BackgroundTasks`, собранный как чистая композиция
`spawn`/`supervised` — ни одного нового примитива рантайма. `bg.add(task)`
ставит в очередь `fn() -> ()`, FIFO; `resp.background(bg)` (fluent-сеттер
`mut @background(tasks) -> @` на `ServerResponse`) прикрепляет коллектор к
ответу. Драйвер соединения (`handle_connection`/`serve_connection`)
вызывает `@drain()` **после** того, как байты ответа полностью записаны
клиенту — очередь работы никогда не добавляет латентности хендлеру. Задачи
выполняются **по одной**, каждая в своём `supervised`-scope: паникующая
задача изолирована (залогирована через `@sink(f)`, по умолчанию stdout),
не останавливает задачи, поставленные после неё, и не роняет процесс.

## Связанные документы

**Полный пример:** [`examples/09-graceful`](../examples/09-graceful) — ручки `ServerPolicy` и `BackgroundTasks`, реально запущенные (см. также [`01-hello`](../examples/01-hello) — минимальная форма accept-цикла, и [`07-sse-stream`](../examples/07-sse-stream) — потоки/SSE).

- [handlers-response.md](handlers-response.ru.md) — `ServerResponse`, значение, которое в итоге пишет `serve_router`
- [errors.md](errors.ru.md) — чем пойманная паника отличается по форме от `HttpError`
- [roadmap.md](roadmap.ru.md) — graceful-shutdown с дедлайном для фоновых задач (пока не подключён)
- [`src/net/`](../src/net), [`src/serve/serve.nv`](../src/serve/serve.nv), [`src/background.nv`](../src/background.nv), [`src/background_test.nv`](../src/background_test.nv)
