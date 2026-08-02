<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# 12-https/certs — self-signed `localhost` fixture

Same pattern `nova/examples/tls/certs/` uses for the plain `nova-tls`
example: `localhost_cert.pem`/`localhost_key.pem` are copied verbatim from
`nova-tls`'s own `src/testdata/` (self-signed ECDSA P-256, `CN=localhost`,
SAN `DNS:localhost, IP:127.0.0.1`, 100-year validity so it never expires in
a demo run) — **test-only fixture**, the private key is intentionally
public. `src/main.nv` pulls both files in at compile time via `embed(...)`
(D412), no filesystem/`Fs` effect needed at runtime.

Regenerate (or roll your own for anything real) with the recipe documented
at `nova-tls/src/testdata/README.md` — do not reuse this exact key pair
outside tests/demos.
