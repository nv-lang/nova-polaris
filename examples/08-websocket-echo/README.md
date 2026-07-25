# 08 — websocket-echo

A real RFC 6455 handshake and echo loop over a live loopback socket, through
the canonical `Router` + `WebSocketUpgrade` extractor: `WebSocketUpgrade.
from_request`, `.on_upgrade(h)`, `WebSocket.recv()`/`.send()`/`.close()`.

By way of: axum's `websockets` example.

## Run

```sh
nova build --strict-effects src/main.nv
./main   # binds 0.0.0.0:18089
```

```sh
curl http://localhost:18089/health   # ok  (any non-upgrade request)
```

A WebSocket client is needed for the echo itself — `curl` alone can't drive
one. Any client works, e.g. browser devtools' own
`new WebSocket("ws://localhost:18089/ws")` (the easiest way to try
`.send()`/`.onmessage` interactively), or PowerShell's
`System.Net.WebSockets.ClientWebSocket`.

## `main()`, same shape as every other example

```nova
fn ws_echo_handler(req ServerRequest) -> ServerResponse {
    match WebSocketUpgrade.from_request(req) {
        Ok(up) => up.on_upgrade(fn(sock WebSocket) Net -> () { ... })
        Err(e) => e.into_response()
    }
}
```

`WebSocketUpgrade.from_request` is a normal `FromRequest` extractor — a
malformed upgrade request (wrong method, missing `Sec-WebSocket-Key`, etc.)
is a typed 400, no socket work happens. `up.on_upgrade(h)` writes the `101
Switching Protocols` response, then hands the live `WebSocket` to `h`, which
owns it from then on (`consume`, D133 — forgetting to close is a compile
error, not a leak). `serve_router`'s own connection driver
(`polaris.net.serve_connection`'s `run_request`) checks for this hook right
after those 101 bytes are on the wire and hands off the live socket instead
of the normal keep-alive continuation — no hand-rolled accept loop needed;
`main()` here is the exact same `serve_router(listener, app,
ServerPolicy.new())` shape every other example in this set uses (see
[`examples/README.md`](../README.md)). Live end-to-end proof of this exact
wiring: [`src/rt/ws_upgrade_hijack_smoke.nv`](../../src/rt/ws_upgrade_hijack_smoke.nv).

## What to poke at

- Send a `Ping` frame — `WebSocket` answers it with an automatic `Pong`
  before your next `.recv()` even sees it (see
  [`docs/websocket.md`](../../docs/websocket.md#automatic-protocol-behavior)).
- Send a fragmented message (two frames, `FIN=0` then `FIN=1`) — reassembled
  transparently into one `Message` on the receiving end.

## Related documentation

- [`docs/websocket.md`](../../docs/websocket.md) — `WebSocketUpgrade`, `WebSocket`, automatic protocol behavior, scope

[Русский](README.ru.md) · see [`examples/README.md`](../README.md) for `main()`'s canonical `serve_router` shape.
