# tokio-tungstenite-wasm (vendored)

Upstream [tokio-tungstenite-wasm v0.8.2](https://github.com/TannerRogalsky/tokio-tungstenite-wasm) with a minimal patch:

- `connect_request(req)` — native handshake from a pre-built `http::Request`
- `connect_request_tls(req, connector)` — same with a custom TLS connector
