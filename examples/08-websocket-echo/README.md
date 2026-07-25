# 08 — websocket-echo

A real RFC 6455 handshake and echo loop over a live loopback socket:
`ws_accept_key`, `WebSocket.with_limit`, `.recv()`/`.send()`/`.close()`.

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
one. A five-line Python client:

```python
import socket, base64
s = socket.create_connection(("127.0.0.1", 18089))
key = base64.b64encode(b"0123456789012345").decode()
s.sendall(f"GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode())
print(s.recv(200))   # HTTP/1.1 101 Switching Protocols ...
```

(browser devtools' own `new WebSocket("ws://localhost:18089/ws")` works too,
and is the easiest way to try `.send()`/`.onmessage` interactively.)

## Why this example doesn't use `Router`

Every other example in this set registers routes on a `Router` and drives
connections through `polaris.serve.handle_connection_router`. The
documented WebSocket idiom
([`docs/websocket.md`](../../docs/websocket.md)) — a `WebSocketUpgrade`
`Router` extractor whose `@on_upgrade(h)` hands the live socket to `h` — is
real and IS wired end-to-end (see this package's own
[`src/rt/ws_upgrade_hijack_smoke.nv`](../../src/rt/ws_upgrade_hijack_smoke.nv)),
but only through `polaris.net.serve_connection`/`serve_router` — the same
per-request-supervised connection driver every other example's
`production_main()` names as currently un-linkable in this toolchain
snapshot (`undefined symbol: nova_fn_hook`). So this example instead drives
the handshake and the `WebSocket` object directly against the accepted
socket by hand — the exact shape this package's own live-socket protocol
proof, [`src/ws/rt/socket_echo_smoke.nv`](../../src/ws/rt/socket_echo_smoke.nv),
already uses, unaffected by the gap above. Once `serve_router` links again,
this example's `main()` collapses to the `Router` + `WebSocketUpgrade`
extractor shape `docs/websocket.md` documents — nothing about the protocol
layer itself (`polaris.ws`) changes.

## What to poke at

- Send a `Ping` frame — `WebSocket` answers it with an automatic `Pong`
  before your next `.recv()` even sees it (see
  [`docs/websocket.md`](../../docs/websocket.md#automatic-protocol-behavior)).
- Send a fragmented message (two frames, `FIN=0` then `FIN=1`) — reassembled
  transparently into one `Message` on the receiving end.

## Related documentation

- [`docs/websocket.md`](../../docs/websocket.md) — `WebSocketUpgrade`, `WebSocket`, automatic protocol behavior, scope

[Русский](README.ru.md)
