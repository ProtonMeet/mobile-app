//! Native WebSocket connect helpers with Bearer auth.
//!
//! WASM uses cookie-based auth via [`super::ws_client`] instead; these helpers
//! only exist because browsers cannot set arbitrary handshake headers.

#[cfg(not(target_family = "wasm"))]
use http::header::AUTHORIZATION;
#[cfg(not(target_family = "wasm"))]
use tokio_tungstenite::{tungstenite::client::IntoClientRequest, Connector};
#[cfg(not(target_family = "wasm"))]
use tokio_tungstenite_wasm::{Error, Result, WebSocketStream};

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
