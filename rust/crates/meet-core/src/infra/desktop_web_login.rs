//! Desktop web login via account session fork (`/auth/v4/sessions/forks`).
//! Native-only — not used on WASM.

use aes_gcm::aead::generic_array::GenericArray;
use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::Engine;
use muon::app::AppVersion;
use muon::auth::{Auth, WithCodeFlow, WithCodePollFlow};
use muon::env::Env;
use muon::Environment;
use rand::RngCore;
use serde::Deserialize;

use crate::errors::core::MeetCoreError;
use crate::infra::dto::proton_user::UserData;
use crate::infra::http_client::ProtonHttpClient;
use crate::infra::muon::SharedAuth;
use crate::infra::muon::{MeetContext, MeetSession};

const CHILD_CLIENT_ID_MAX_LEN: usize = 64;

/// Fork payload version requested of account: 12-byte IV, `fork` as AES-GCM context.
const PAYLOAD_VERSION: u8 = 3;

/// Custom URL scheme the system browser returns to after account deposits the fork.
const BROWSER_REDIRECT_SCHEME: &str = "protonmeet";

#[derive(Debug)]
pub struct DesktopWebLoginStart {
    pub login_url: String,
    /// Opaque value embedded in [browser redirect URL](redirect_url); match on deep link callback.
    pub browser_redirect_state: String,
}

#[derive(Debug)]
pub enum DesktopWebLoginPoll {
    Pending,
    Complete {
        user_data: Box<UserData>,
        mailbox_password: String,
        auth: Auth,
    },
}

pub struct PendingState {
    poll_flow: WithCodePollFlow<MeetContext>,
    encryption_key: [u8; 32],
    login_auth: SharedAuth,
}

#[derive(Debug, Deserialize)]
struct SessionPayload {
    #[serde(rename = "keyPassword")]
    key_password: String,
}

/// AES-GCM additional data for fork payload version 3.
const FORK_PAYLOAD_AAD: &[u8] = b"fork";

const V3_NONCE_LEN: usize = 12;

fn generate_encryption_key() -> [u8; 32] {
    let mut key = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut key);
    key
}

fn account_url_for_env(env: &Environment) -> Result<String, MeetCoreError> {
    match env {
        Environment::Prod(_) => Ok("https://account.proton.me".to_string()),
        Environment::Atlas(_) => Ok("https://account.proton.black".to_string()),
        Environment::Scientist(_) => {
            let app_version: AppVersion =
                "macos-meet@0.0.1"
                    .parse()
                    .map_err(|_| MeetCoreError::AuthenticationFailed {
                        message: "Failed to resolve atlas scientist environment".to_string(),
                    })?;
            let servers = env.servers(&app_version);
            let scientist = servers
                .first()
                .and_then(|server| server.host().strip_suffix(".proton.black"))
                .and_then(|prefix| prefix.rsplit('.').next())
                .ok_or_else(|| MeetCoreError::AuthenticationFailed {
                    message: "Failed to resolve atlas scientist environment".to_string(),
                })?;
            Ok(format!("https://account.{scientist}.proton.black"))
        }
        Environment::Custom(_) => Err(MeetCoreError::AuthenticationFailed {
            message: "Desktop web login is not supported for custom environments".to_string(),
        }),
    }
}

/// Percent-encode everything outside the URL unreserved set.
///
/// The payload rides in a fragment that account parses with `URLSearchParams`, which decodes
/// `+` to a space, so standard-alphabet base64 cannot be passed through raw.
fn percent_encode(value: &str) -> String {
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                encoded.push(byte as char)
            }
            _ => encoded.push_str(&format!("%{byte:02X}")),
        }
    }
    encoded
}

/// The product half of a `<platform>-<product>` client ID, used as account's `app` value.
fn app_param(client_id: &str) -> Result<&str, MeetCoreError> {
    client_id
        .split_once('-')
        .map(|(_platform, product)| product)
        .filter(|product| !product.is_empty())
        .ok_or_else(|| MeetCoreError::AuthenticationFailed {
            message: format!("client ID '{client_id}' is not <platform>-<product>"),
        })
}

fn random_base64url(bytes: usize) -> String {
    let mut buffer = vec![0u8; bytes];
    rand::thread_rng().fill_bytes(&mut buffer);
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(buffer)
}

/// Where account sends the browser once it has deposited the fork.
///
/// The `state` is ours, so it returns regardless of what account appends — it does not append
/// the `UserCode` its documentation shows. It carries nothing sensitive: a hostile claimant of
/// the scheme learns only a random string.
fn redirect_url(state: &str) -> String {
    format!("{BROWSER_REDIRECT_SCHEME}://login?state={state}")
}

fn build_login_url(
    env: &Environment,
    user_code: &str,
    encryption_key: &[u8],
    child_client_id: &str,
    redirect: &str,
) -> Result<String, MeetCoreError> {
    if child_client_id.is_empty() || child_client_id.len() > CHILD_CLIENT_ID_MAX_LEN {
        return Err(MeetCoreError::AuthenticationFailed {
            message: "Invalid desktop child client id".to_string(),
        });
    }

    let account_url = account_url_for_env(env)?;
    let encoded_key = base64::engine::general_purpose::STANDARD.encode(encryption_key);
    let payload = format!("0:{user_code}:{encoded_key}:{child_client_id}");

    Ok(format!(
        "{}/desktop/login?app={}&pv={PAYLOAD_VERSION}&redirectUrl={}#payload={}",
        account_url.trim_end_matches('/'),
        app_param(child_client_id)?,
        percent_encode(redirect),
        percent_encode(&payload),
    ))
}

fn decrypt_payload(encryption_key: &[u8], payload: Option<&[u8]>) -> Result<String, MeetCoreError> {
    let ciphertext = payload.ok_or_else(|| MeetCoreError::AuthenticationFailed {
        message: "Desktop login response missing payload".to_string(),
    })?;

    // Payload version 3: 12-byte IV, ciphertext+tag, AAD `fork` (matches WebApp getDecryptedBlobV3).
    if ciphertext.len() < V3_NONCE_LEN + 16 {
        return Err(MeetCoreError::AuthenticationFailed {
            message: "Desktop login payload is too short".to_string(),
        });
    }

    let (nonce_bytes, cipherdata) = ciphertext.split_at(V3_NONCE_LEN);
    let cipher = Aes256Gcm::new(GenericArray::from_slice(encryption_key));
    let nonce = Nonce::from_slice(nonce_bytes);
    let decrypted = cipher
        .decrypt(
            nonce,
            Payload {
                msg: cipherdata,
                aad: FORK_PAYLOAD_AAD,
            },
        )
        .map_err(|e| MeetCoreError::AuthenticationFailed {
            message: format!("Failed to decrypt desktop login payload: {e}"),
        })?;

    let parsed: SessionPayload =
        serde_json::from_slice(&decrypted).map_err(|e| MeetCoreError::AuthenticationFailed {
            message: format!("Failed to parse desktop login payload: {e}"),
        })?;

    Ok(parsed.key_password)
}

pub async fn start(
    http_client: &ProtonHttpClient,
    child_client_id: String,
) -> Result<(DesktopWebLoginStart, PendingState), MeetCoreError> {
    let (login_client, login_auth) =
        http_client.new_isolated_login_client().await.map_err(|e| {
            MeetCoreError::AuthenticationFailed {
                message: format!("Failed to create desktop login session: {e}"),
            }
        })?;

    let env = login_client.env().clone();

    let poll_flow = match login_client.auth().from_fork().with_code().await {
        WithCodeFlow::Poll(poll_flow) => poll_flow,
        WithCodeFlow::Ok(_, _) => {
            return Err(MeetCoreError::AuthenticationFailed {
                message: "Unexpected desktop web login fork response".to_string(),
            })
        }
        WithCodeFlow::Failed { reason, .. } => {
            tracing::error!("Desktop web login failed: {reason}");
            return Err(MeetCoreError::AuthenticationFailed {
                message: "Unexpected desktop web login fork response".to_string(),
            });
        }
    };

    let encryption_key = generate_encryption_key();
    let browser_redirect_state = random_base64url(16);
    let login_url = build_login_url(
        &env,
        poll_flow.code(),
        &encryption_key,
        &child_client_id,
        &redirect_url(&browser_redirect_state),
    )?;

    Ok((
        DesktopWebLoginStart {
            login_url,
            browser_redirect_state,
        },
        PendingState {
            poll_flow,
            encryption_key,
            login_auth,
        },
    ))
}

pub async fn poll(
    http_client: &ProtonHttpClient,
    pending: PendingState,
) -> Result<(DesktopWebLoginPoll, Option<PendingState>), MeetCoreError> {
    match pending.poll_flow.poll().await {
        WithCodeFlow::Poll(poll_flow) => Ok((
            DesktopWebLoginPoll::Pending,
            Some(PendingState {
                poll_flow,
                encryption_key: pending.encryption_key,
                login_auth: pending.login_auth,
            }),
        )),
        WithCodeFlow::Ok(session, payload) => {
            session.client().sync_stores().await;
            let auth = pending.login_auth.lock().await.clone();
            let mailbox_password = decrypt_payload(&pending.encryption_key, payload.as_deref())?;
            let user_data = fetch_user_data(http_client, &session).await?;
            Ok((
                DesktopWebLoginPoll::Complete {
                    user_data: Box::new(user_data),
                    mailbox_password,
                    auth,
                },
                None,
            ))
        }
        WithCodeFlow::Failed { reason, .. } => Err(MeetCoreError::AuthenticationFailed {
            message: format!("Desktop web login failed: {reason}"),
        }),
    }
}

async fn fetch_user_data(
    http_client: &ProtonHttpClient,
    session: &MeetSession,
) -> Result<UserData, MeetCoreError> {
    http_client
        .get_user_data(session)
        .await
        .map_err(|e| MeetCoreError::AuthenticationFailed {
            message: format!("Failed to load user after desktop login: {e}"),
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use muon::Environment;

    #[test]
    fn login_url_percent_encodes_the_payload_fragment() {
        let env = Environment::Prod(Default::default());
        let url = build_login_url(
            &env,
            "ABCD1234",
            &[0xFF, 0xFE],
            "macos-meet",
            "protonmeet://login?state=abc",
        )
        .unwrap();

        let fragment = url.split('#').nth(1).unwrap();
        assert!(!fragment.contains('/'));
        assert!(fragment.contains("%2F%2F4%3D"));
    }

    #[test]
    fn login_url_carries_user_code_and_client_id() {
        let env = Environment::Prod(Default::default());
        let url = build_login_url(
            &env,
            "USERCODE",
            &[0u8; 32],
            "macos-meet",
            "protonmeet://login",
        )
        .unwrap();
        let payload = url.split("#payload=").nth(1).unwrap();

        assert!(payload.starts_with("0%3AUSERCODE%3A"));
        assert!(payload.ends_with("%3Amacos-meet"));
    }

    #[test]
    fn redirect_url_goes_in_the_query_not_the_fragment() {
        let env = Environment::Prod(Default::default());
        let url = build_login_url(
            &env,
            "CODE",
            &[0u8; 32],
            "macos-meet",
            "protonmeet://login?state=abc",
        )
        .unwrap();

        let (query, fragment) = url.split_once('#').unwrap();
        assert!(query.contains("&redirectUrl=protonmeet%3A%2F%2Flogin%3Fstate%3Dabc"));
        assert!(!fragment.contains("redirectUrl"));
    }

    #[test]
    fn app_param_is_the_product_half_of_the_client_id() {
        assert_eq!(app_param("macos-meet").unwrap(), "meet");
        assert_eq!(app_param("windows-meet").unwrap(), "meet");
        assert!(app_param("meet").is_err());
        assert!(app_param("macos-").is_err());
    }

    #[test]
    fn login_url_includes_payload_version() {
        let env = Environment::Prod(Default::default());
        let url = build_login_url(
            &env,
            "CODE",
            &[0u8; 32],
            "macos-meet",
            "protonmeet://login?state=abc",
        )
        .unwrap();

        assert!(url.contains("&pv=3&redirectUrl="));
    }

    #[test]
    fn generated_redirect_state_values_are_unpredictable() {
        assert_ne!(random_base64url(16), random_base64url(16));
    }

    #[test]
    fn decrypt_payload_handles_version_3_fork_blob() {
        use aes_gcm::aead::{Aead, KeyInit, Payload};
        use aes_gcm::Aes256Gcm;

        let key = [7u8; 32];
        let plaintext = br#"{"keyPassword":"mailbox-secret"}"#;
        let cipher = Aes256Gcm::new(GenericArray::from_slice(&key));
        let nonce = Nonce::from_slice(&[1u8; V3_NONCE_LEN]);
        let mut blob = nonce.to_vec();
        blob.extend_from_slice(
            &cipher
                .encrypt(
                    nonce,
                    Payload {
                        msg: plaintext,
                        aad: FORK_PAYLOAD_AAD,
                    },
                )
                .unwrap(),
        );

        let password = decrypt_payload(&key, Some(&blob)).unwrap();
        assert_eq!(password, "mailbox-secret");
    }
}
