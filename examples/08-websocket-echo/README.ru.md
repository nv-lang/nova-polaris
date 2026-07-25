# 08 — websocket-echo

Настоящий RFC 6455 handshake и echo-цикл по живому loopback-сокету:
`ws_accept_key`, `WebSocket.with_limit`, `.recv()`/`.send()`/`.close()`.

По мотивам: `websockets`-пример axum.

## Запуск

```sh
nova build --strict-effects src/main.nv
./main   # слушает 0.0.0.0:18089
```

```sh
curl http://localhost:18089/health   # ok  (любой не-upgrade запрос)
```

Для самого echo нужен WebSocket-клиент — один `curl` его не проведёт.
Пятистрочный Python-клиент:

```python
import socket, base64
s = socket.create_connection(("127.0.0.1", 18089))
key = base64.b64encode(b"0123456789012345").decode()
s.sendall(f"GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode())
print(s.recv(200))   # HTTP/1.1 101 Switching Protocols ...
```

(свой `new WebSocket("ws://localhost:18089/ws")` в devtools браузера тоже
работает и проще всего для интерактивного `.send()`/`.onmessage`).

## Почему этот пример не использует `Router`

Каждый другой пример этого набора регистрирует маршруты на `Router` и
ведёт соединения через `polaris.serve.handle_connection_router`.
Задокументированный WebSocket-идиом
([`docs/websocket.ru.md`](../../docs/websocket.ru.md)) — экстрактор
`WebSocketUpgrade` для `Router`, чей `@on_upgrade(h)` передаёт живой сокет
в `h` — реален и ДЕЙСТВИТЕЛЬНО подключён от начала до конца (см. собственный
тест пакета
[`src/rt/ws_upgrade_hijack_smoke.nv`](../../src/rt/ws_upgrade_hijack_smoke.nv)),
но только через `polaris.net.serve_connection`/`serve_router` — тот же
драйвер соединения с супервизией на запрос, который каждый другой пример
называет в своём `production_main()` как сейчас не линкующийся на этом
снимке тулчейна (`undefined symbol: nova_fn_hook`). Поэтому этот пример
вместо этого ведёт handshake и объект `WebSocket` вручную, напрямую по
принятому сокету — точно та же форма, что уже использует собственное
доказательство протокольного слоя на живом сокете этого пакета,
[`src/ws/rt/socket_echo_smoke.nv`](../../src/ws/rt/socket_echo_smoke.nv), —
пробел выше его не задевает. Как только `serve_router` снова залинкуется,
`main()` этого примера схлопнется до формы `Router` + экстрактор
`WebSocketUpgrade`, задокументированной в `docs/websocket.md` — сам
протокольный слой (`polaris.ws`) при этом не меняется.

## Что покрутить

- Пошли фрейм `Ping` — `WebSocket` отвечает автоматическим `Pong` ещё до
  того, как твой следующий `.recv()` его увидит (см.
  [`docs/websocket.ru.md`](../../docs/websocket.ru.md#автоматическое-поведение-протокола)).
- Пошли фрагментированное сообщение (два фрейма, `FIN=0` затем `FIN=1`) —
  на приёмной стороне прозрачно пересобирается в одно `Message`.

## Связанная документация

- [`docs/websocket.ru.md`](../../docs/websocket.ru.md) — `WebSocketUpgrade`, `WebSocket`, автоматическое поведение протокола, границы

[English](README.md)
