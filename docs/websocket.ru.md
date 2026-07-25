# WebSocket

[English](websocket.md) | **Русский**

`polaris.ws` реализует протокол RFC 6455 (открывающий handshake, кодек
фреймов, пересборку фрагментации, живой объект соединения); серверный
extractor `WebSocketUpgrade` живёт в корневом модуле `polaris`, рядом с
любым другим extractor'ом.

Исходник: [`src/ws/handshake.nv`](../src/ws/handshake.nv),
[`src/ws/frame.nv`](../src/ws/frame.nv), [`src/ws/socket.nv`](../src/ws/socket.nv),
[`src/ws_upgrade.nv`](../src/ws_upgrade.nv).

---

## Содержание

- [Апгрейд запроса](#апгрейд-запроса)
- [Объект соединения `WebSocket`](#объект-соединения-websocket)
- [Автоматическое протокольное поведение](#автоматическое-протокольное-поведение)
- [Объём](#объём)
- [Связанные документы](#связанные-документы)

---

## Апгрейд запроса

```nova
fn ws_echo_handler(req ServerRequest) -> ServerResponse {
    match WebSocketUpgrade.from_request(req) {
        Ok(up) => up.on_upgrade(fn(sock WebSocket) Net -> () {
            mut ws = sock
            mut running = true
            while running {
                match ws.recv() {
                    Ok(Some(Message.Text(t))) => { ro _ = ws.send(Message.Text(t)) } // echo
                    Ok(Some(_))                => ()                                  // Ping already auto-Ponged
                    Ok(None)                   => { running = false }
                    Err(_)                     => { running = false }
                }
            }
            ro _ = ws.close(1000, "bye")
        })
        Err(e) => e.into_response()
    }
}
```

`WebSocketUpgrade.from_request` (обычный extractor `FromRequest`, см.
[handlers-response.md](handlers-response.ru.md)) проверяет, что запрос —
корректный апгрейд: метод `GET`, `Upgrade: websocket`,
`Connection: Upgrade`, `Sec-WebSocket-Version: 13`, присутствующий
`Sec-WebSocket-Key` — и захватывает то, что нужно для handshake; битый
запрос — типизированная `HttpError` (400), как и отказ любого другого
extractor'а, ещё до какой-либо работы с сокетом.

`up.on_upgrade(h)` строит ответ `101 Switching Protocols` (вычисленный
`Sec-WebSocket-Accept`, эхо предложенного subprotocol, если есть) и
устанавливает `h` как хук, который драйвер соединения вызывает **после**
того, как эти байты 101 уже на проводе — `h` получает живой `WebSocket`,
владеет им с этого момента и обязан вызвать `@close()` (тип `consume` —
забыть закрыть — это ошибка **компиляции**, D133, в отличие от
socket-дескриптора с leak-by-default).

Эта функция сознательно компилируется, но никогда не вызывается из блока
`test { }` — реальному апгрейду нужен настоящий TCP handshake. Живое
доказательство живёт в собственном тестовом наборе пакета:
[`src/ws/rt/socket_echo_smoke.nv`](../src/ws/rt/socket_echo_smoke.nv)
проводит настоящий loopback-эхо ровно по этой форме, а
[`src/rt/ws_upgrade_hijack_smoke.nv`](../src/rt/ws_upgrade_hijack_smoke.nv)
доказывает подключение хука через настоящий `Router` + драйвер соединения
целиком.

```nova
test "websocket: a non-upgrade request is rejected before any socket work" {
    mut r = Router.new()
    r.get("/ws", ws_echo_handler)!!
    ro wire = serve_once(r, get_req("/ws"))
    assert(status_line(wire) != "HTTP/1.1 101 Switching Protocols")
}
```

## Объект соединения `WebSocket`

| Метод | Сигнатура | Заметки |
|---|---|---|
| `mut @recv` | `() Net -> Result[Option[Message], WsError]` | `None` = собеседник закрылся чисто (close-handshake уже отправлен эхом) |
| `mut @send` | `(m Message) Net -> Result[(), WsError]` | всегда отправляется немаскированным (роль сервера) |
| `consume @close` | `(code u16, reason str) Net -> Result[(), WsError]` | единственный способ погасить значение |

`Message` — это `Text(str) | Binary([]u8) | Ping([]u8) | Pong([]u8)` —
фреймы `Continuation` никогда не выходят за пределы этого слоя, они —
внутренняя механика пересборки. `WebSocket.with_limit(stream, max_message_size)`
задаёт защиту от DoS (по умолчанию 16 МиБ, `WebSocket.new` использует
именно её); лимит применяется к текущей сумме на протяжении
фрагментированного сообщения, а не только к финальному размеру.

## Автоматическое протокольное поведение

Не оставлено на откуп вызывающему коду (иначе соответствие RFC 6455 было
бы легко тонко нарушить в каждом отдельном приложении):

- **Ping → автоматический Pong** — полученный `Ping` отвечается до того, как
  `@recv()` его вернёт (по-прежнему передаётся вызывающему как
  `Message.Ping`, информационно).
- **Фрагментация пересобирается** — многофреймовое сообщение возвращается
  из `@recv()` как одно `Message`; управляющие фреймы (Ping/Pong/Close)
  легально могут перемежаться посреди фрагментации и обрабатываются на
  месте.
- **Close-handshake** — получение фрейма `Close` отправляет его эхом
  обратно, прежде чем `@recv()` сообщит о чистом конце потока (`Ok(None)`).
- **Серверная маскировка обязательна** — немаскированный фрейм от клиента
  отклоняется (`WsError.UnmaskedClientFrame`); сервер всегда отправляет
  немаскированные.

## Объём

Только серверная сторона (WebSocket-**клиент** для Nova не реализован);
`permessage-deflate` не реализован. `WebSocketUpgrade` сознательно не
проводит переговоры между несколькими предложенными subprotocol'ами — он
эхом отдаёт **первый** предложенный, если есть; выбор другого — дело
вызывающего кода (`up.accept_response(Some(proto))` принимает явный выбор,
если нужно переопределить эхо).

## Связанные документы

- [handlers-response.md](handlers-response.ru.md) — `FromRequest`, протокол, который реализует `WebSocketUpgrade`
- [errors.md](errors.ru.md) — `HttpError` от неудавшегося апгрейда
- [`src/ws/`](../src/ws), [`src/ws_upgrade.nv`](../src/ws_upgrade.nv), [`src/ws_upgrade_test.nv`](../src/ws_upgrade_test.nv)
