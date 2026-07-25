# WebSocket

**English** | [Русский](websocket.ru.md)

`polaris.ws` implements the RFC 6455 protocol (opening handshake, frame
codec, fragmentation reassembly, the live connection object); the server-side
`WebSocketUpgrade` extractor lives in the root `polaris` module, next to
every other extractor.

Source: [`src/ws/handshake.nv`](../src/ws/handshake.nv),
[`src/ws/frame.nv`](../src/ws/frame.nv), [`src/ws/socket.nv`](../src/ws/socket.nv),
[`src/ws_upgrade.nv`](../src/ws_upgrade.nv).

---

## Contents

- [Upgrading a request](#upgrading-a-request)
- [The `WebSocket` connection object](#the-websocket-connection-object)
- [Automatic protocol behavior](#automatic-protocol-behavior)
- [Scope](#scope)
- [Related documents](#related-documents)

---

## Upgrading a request

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

`WebSocketUpgrade.from_request` (a normal `FromRequest` extractor, see
[handlers-response.md](handlers-response.md)) validates the request is a
well-formed upgrade — method `GET`, `Upgrade: websocket`, `Connection: Upgrade`,
`Sec-WebSocket-Version: 13`, a present `Sec-WebSocket-Key` — and captures
what the handshake needs; a malformed request is a typed `HttpError` (400)
like any other extractor failure, before any socket work happens.

`up.on_upgrade(h)` builds the `101 Switching Protocols` response (computed
`Sec-WebSocket-Accept`, offered subprotocol echoed back if any) and installs
`h` as a hook the connection driver calls **after** those 101 bytes are on
the wire — `h` receives the live `WebSocket`, owns it from then on, and is
responsible for `@close()`-ing it (a `consume` type — forgetting to close is
a **compile** error, D133, unlike a leak-by-default socket handle).

This function is intentionally compiled but never called from a `test { }`
block — a real upgrade needs an actual TCP handshake. The live proof lives
in this package's own test suite:
[`src/ws/rt/socket_echo_smoke.nv`](../src/ws/rt/socket_echo_smoke.nv) drives
a real loopback echo through this exact shape, and
[`src/rt/ws_upgrade_hijack_smoke.nv`](../src/rt/ws_upgrade_hijack_smoke.nv)
proves the hook wiring through a real `Router` + connection driver end to
end.

```nova
test "websocket: a non-upgrade request is rejected before any socket work" {
    mut r = Router.new()
    r.get("/ws", ws_echo_handler)!!
    ro wire = serve_once(r, get_req("/ws"))
    assert(status_line(wire) != "HTTP/1.1 101 Switching Protocols")
}
```

## The `WebSocket` connection object

| Method | Signature | Notes |
|---|---|---|
| `mut @recv` | `() Net -> Result[Option[Message], WsError]` | `None` = peer closed cleanly (close handshake already echoed) |
| `mut @send` | `(m Message) Net -> Result[(), WsError]` | always sent unmasked (server role) |
| `consume @close` | `(code u16, reason str) Net -> Result[(), WsError]` | the only way to discharge the value |

`Message` is `Text(str) | Binary([]u8) | Ping([]u8) | Pong([]u8)` —
`Continuation` frames never escape this layer, they are reassembly
plumbing. `WebSocket.with_limit(stream, max_message_size)` sets a DoS guard
(default 16 MiB, `WebSocket.new` uses it); the limit applies to the running
total across a fragmented message, not just the final size.

## Automatic protocol behavior

Not left to the caller (RFC 6455 compliance would otherwise be easy to get
subtly wrong per-application):

- **Ping → automatic Pong** — a received `Ping` is answered before `@recv()`
  returns it (still surfaced to the caller as `Message.Ping`, informationally).
- **Fragmentation reassembled** — a multi-frame message comes back from
  `@recv()` as one `Message`; control frames (Ping/Pong/Close) may legally
  interleave mid-fragmentation and are handled in place.
- **Close handshake** — receiving a `Close` frame echoes one back before
  `@recv()` reports the clean end-of-stream (`Ok(None)`).
- **Server-role masking enforced** — an unmasked frame from a client is
  rejected (`WsError.UnmaskedClientFrame`); the server always sends unmasked.

## Scope

Server-side only (a Nova WebSocket **client** is not implemented);
`permessage-deflate` is not implemented. `WebSocketUpgrade` deliberately
does not negotiate among several offered subprotocols — it echoes the
**first** offered one, if any; picking a different one is the caller's
business (`up.accept_response(Some(proto))` takes an explicit choice if you
need to override the echo).

## Related documents

**Full example:** [`examples/08-websocket-echo`](../examples/08-websocket-echo) — a real RFC 6455 handshake + echo loop over a live socket.

- [handlers-response.md](handlers-response.md) — `FromRequest`, the protocol `WebSocketUpgrade` implements
- [errors.md](errors.md) — `HttpError` from a failed upgrade
- [`src/ws/`](../src/ws), [`src/ws_upgrade.nv`](../src/ws_upgrade.nv), [`src/ws_upgrade_test.nv`](../src/ws_upgrade_test.nv)
