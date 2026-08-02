<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# src/net/testdata — TLS fixture for `servernet_tls_test.nv`

`localhost_cert.pem`/`localhost_key.pem` are copied verbatim from
`nova-tls`'s own `src/testdata/` (self-signed ECDSA P-256, `CN=localhost`,
SAN `DNS:localhost, IP:127.0.0.1`, 100-year validity) — same fixture as
`examples/12-https/certs/`, same rationale: **test-only**, the private key
is intentionally public. `servernet_tls_test.nv` embeds both via
`embed(...)` (D412), no `Fs` effect needed.

Regenerate with the recipe at `nova-tls/src/testdata/README.md`.
