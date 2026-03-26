#[cfg(feature = "insecure-tls")]
pub fn dev_reqwest_builder() -> reqwest::ClientBuilder {
    // OK for local/dev only. Don't use in production.
    #[cfg(not(target_family = "wasm"))]
    return reqwest::Client::builder()
        .danger_accept_invalid_certs(true)
        .danger_accept_invalid_hostnames(true)
        .use_rustls_tls();

    #[cfg(target_family = "wasm")]
    return reqwest::Client::builder();
}
