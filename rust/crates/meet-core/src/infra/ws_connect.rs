//! Native WebSocket connect helpers with Bearer auth.
//!
//! WASM uses cookie-based auth via [`super::ws_client`] instead; these helpers
//! only exist because browsers cannot set arbitrary handshake headers.

#[cfg(not(target_family = "wasm"))]
use http::header::AUTHORIZATION;
#[cfg(not(target_family = "wasm"))]
use tokio_tungstenite::{Connector, tungstenite::client::IntoClientRequest};
#[cfg(not(target_family = "wasm"))]
use tokio_tungstenite_wasm::{Error, Result, WebSocketStream};

/// Use native OpenSSL to avoid `HandshakeFailure` on Atlas hosts.
#[cfg(all(not(target_family = "wasm"), feature = "insecure-tls"))]
pub fn insecure_native_tls_connector() -> Result<Connector, native_tls::Error> {
    let tls = native_tls::TlsConnector::builder()
        .danger_accept_invalid_certs(true)
        .danger_accept_invalid_hostnames(true)
        .build()?;
    Ok(Connector::NativeTls(tls))
}

#[cfg(not(target_family = "wasm"))]
fn auth_request(url: &str, auth: &str) -> Result<http::Request<()>> {
    let mut req = IntoClientRequest::into_client_request(url).map_err(Error::from)?;
    req.headers_mut().insert(
        AUTHORIZATION,
        http::HeaderValue::from_str(&format!("Bearer {auth}")).map_err(Error::from)?,
    );
    Ok(req)
}

#[cfg(not(target_family = "wasm"))]
pub async fn connect_with_auth(url: &str, auth: &str) -> Result<WebSocketStream> {
    tokio_tungstenite_wasm::connect_request(auth_request(url, auth)?).await
}

#[cfg(not(target_family = "wasm"))]
pub async fn connect_with_tls_auth(
    url: &str,
    auth: &str,
    connector: Option<Connector>,
) -> Result<WebSocketStream> {
    tokio_tungstenite_wasm::connect_request_tls(auth_request(url, auth)?, connector).await
}
