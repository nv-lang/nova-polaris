# 08 — websocket-echo

Настоящий RFC 6455 handshake и echo-цикл по живому loopback-сокету, через
канонический экстрактор `Router` + `WebSocketUpgrade`: `WebSocketUpgrade.
from_request`, `.on_upgrade(h)`, `WebSocket.recv()`/`.send()`/`.close()`.

По мотивам: `websockets`-пример axum.

## Запуск

```sh
nova build --strict-effects src/main.nv
./main   # слушает 0.0.0.0:18089
```

```sh
curl http://localhost:18089/health   # ok  (любой не-upgrade запрос)
```

Для самого echo нужен WebSocket-клиент — один `curl` его не проведёт. Подойдёт
любой клиент, например собственный `new WebSocket("ws://localhost:18089/ws")`
в devtools браузера (проще всего для интерактивного `.send()`/`.onmessage`),
или `System.Net.WebSockets.ClientWebSocket` из PowerShell.

## `main()` — та же форма, что и у каждого другого примера

```nova
fn ws_echo_handler(req ServerRequest) -> ServerResponse {
    match WebSocketUpgrade.from_request(req) {
        Ok(up) => up.on_upgrade(fn(sock WebSocket) Net -> () { ... })
        Err(e) => e.into_response()
    }
}
```

`WebSocketUpgrade.from_request` — обычный экстрактор `FromRequest`:
некорректный upgrade-запрос (не тот метод, нет `Sec-WebSocket-Key` и т.п.) —
типизированный 400, никакой работы с сокетом ещё не было. `up.on_upgrade(h)`
пишет ответ `101 Switching Protocols`, затем передаёт живой `WebSocket` в
`h`, который владеет им с этого момента (`consume`, D133 — забыть закрыть —
это ошибка компиляции, а не утечка). Собственный драйвер соединения
`serve_router` (`polaris.net.serve_connection`'s `run_request`) проверяет
этот hook сразу после того, как байты `101` ушли на wire, и передаёт живой
сокет вместо обычного keep-alive-продолжения — никакой ручной accept-цикл
не нужен; `main()` здесь — точно та же форма
`serve_router(listener, app, ServerPolicy.new())`, что и у каждого другого
примера набора (см. [`examples/README.ru.md`](../README.ru.md)). Живое
доказательство именно этой связки от начала до конца:
[`src/rt/ws_upgrade_hijack_smoke.nv`](../../src/rt/ws_upgrade_hijack_smoke.nv).

## Что покрутить

- Пошли фрейм `Ping` — `WebSocket` отвечает автоматическим `Pong` ещё до
  того, как твой следующий `.recv()` его увидит (см.
  [`docs/websocket.ru.md`](../../docs/websocket.ru.md#автоматическое-поведение-протокола)).
- Пошли фрагментированное сообщение (два фрейма, `FIN=0` затем `FIN=1`) —
  на приёмной стороне прозрачно пересобирается в одно `Message`.

## Связанная документация

- [`docs/websocket.ru.md`](../../docs/websocket.ru.md) — `WebSocketUpgrade`, `WebSocket`, автоматическое поведение протокола, границы

[English](README.md) · канонический вид `main()` через `serve_router` — в [`examples/README.ru.md`](../README.ru.md).
