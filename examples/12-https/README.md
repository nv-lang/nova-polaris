# 12 — https

TLS termination in front of a `Router`: same `Router.new()` + one `.get()`
shape as [`01-hello`](../01-hello/), with `polaris.serve.serve_tls` in place
of `serve_router` — a self-signed `localhost` cert, one hello route, served
over HTTPS.

## Run

```sh
nova build --strict-effects src/main.nv
./main   # binds 0.0.0.0:18093
```

```sh
curl -k https://localhost:18093/
# hello, world -- over HTTPS
```

`-k`/`--insecure` is required — `certs/localhost_cert.pem` is a **self-signed
test fixture** (see [`certs/README.md`](certs/README.md)), curl has no CA to
validate it against. A plain (non-TLS) request to the same port fails the
handshake and gets a closed connection + a logged `warn` line server-side —
try `curl http://localhost:18093/` (no `-s` here on purpose: without TLS
curl's own error makes the point) to see it.

## What to poke at

- Point `curl`/a browser at `https://localhost:18093/` and inspect the
  cert — `CN=localhost`, self-signed, valid 100 years (never expires mid-demo).
- Swap `certs/localhost_cert.pem`/`certs/localhost_key.pem` for your own pair
  (`certs/README.md` has the `openssl` recipe) to see the same server present
  a different identity.
- Add a second route the same way `01-hello` does — `serve_tls` routes
  through the SAME `Router` type as every other example, TLS is a transport
  concern underneath it, not a routing one.

## Why this example's `main()` differs from the others

Every other example calls `polaris.serve.serve_router(listener, app,
ServerPolicy.new())` (`../README.md#why-every-mains-looks-the-same-shape`) —
the full keep-alive/`ServerPolicy`-governed accept loop. This example calls
`polaris.serve.serve_tls(addr, tls_cfg, app)` instead: it TLS-handshakes
each accepted connection before ever reaching the router, but — deliberately,
for now — serves ONE request per connection (`Connection: close`), with no
`ServerPolicy` admission/keep-alive knobs. See `serve_tls`'s own doc-comment
(`../../src/serve/serve_tls.nv`) for the full rationale: widening it to
keep-alive+`ServerPolicy` parity with the plaintext path is a follow-up, not
done here.

## Related documentation

- [`docs/overview.md`](../../docs/overview.md) — the plaintext version of
  this exact server, explained
- [`docs/serving.md`](../../docs/serving.md) — `ServerPolicy`, the accept
  loop `serve_tls` deliberately does NOT use yet
- [nova-tls README](https://github.com/nv-lang/nova-tls#readme) — the
  underlying `TlsStream`/`ServerConfig` this example's dependency wires in
- `nova/examples/tls/echo_server.nv` — the same nova-tls dependency used
  bare (no HTTP/`Router` on top), the smallest possible TLS server

[Русский](README.ru.md)
