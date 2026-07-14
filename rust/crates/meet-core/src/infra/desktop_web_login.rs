//! Desktop web login via account session fork (`/auth/v4/sessions/forks`).
//! Native-only — not used on WASM.

use aes::Aes256;
use aes_gcm::aead::consts::U16;
use aes_gcm::aead::generic_array::GenericArray;
use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::AesGcm;
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

#[derive(Debug)]
pub struct DesktopWebLoginStart {
    pub login_url: String,
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

type Aes256GcmWith16ByteNonce = AesGcm<Aes256, U16>;

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

fn build_login_url(
    env: &Environment,
    user_code: &str,
    encryption_key: &[u8],
    child_client_id: &str,
) -> Result<String, MeetCoreError> {
    if child_client_id.is_empty() || child_client_id.len() > CHILD_CLIENT_ID_MAX_LEN {
        return Err(MeetCoreError::AuthenticationFailed {
            message: "Invalid desktop child client id".to_string(),
        });
    }

    let account_url = account_url_for_env(env)?;
    let encoded_key = base64::engine::general_purpose::STANDARD.encode(encryption_key);
    let payload = format!("0:{user_code}:{encoded_key}:{child_client_id}");
    let encoded_payload = urlencoding::encode(&payload);
    Ok(format!(
        "{account_url}/desktop/login?app=meet#payload={encoded_payload}"
    ))
}

fn decrypt_payload(encryption_key: &[u8], payload: Option<&[u8]>) -> Result<String, MeetCoreError> {
    let ciphertext = payload.ok_or_else(|| MeetCoreError::AuthenticationFailed {
        message: "Desktop login response missing payload".to_string(),
    })?;

    if ciphertext.len() < 16 {
        return Err(MeetCoreError::AuthenticationFailed {
            message: "Desktop login payload is too short".to_string(),
        });
    }

    let (nonce_bytes, cipherdata) = ciphertext.split_at(16);
    let cipher = Aes256GcmWith16ByteNonce::new(GenericArray::from_slice(encryption_key));
    let nonce = GenericArray::<u8, U16>::from_slice(nonce_bytes);
    let decrypted = cipher
        .decrypt(
            nonce,
            Payload {
                msg: cipherdata,
                aad: &[],
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
    let WithCodeFlow::Poll(poll_flow) = login_client.auth().from_fork().with_code().await else {
        return Err(MeetCoreError::AuthenticationFailed {
            message: "Unexpected desktop web login fork response".to_string(),
        });
    };

    let encryption_key = generate_encryption_key();
    let login_url = build_login_url(&env, poll_flow.code(), &encryption_key, &child_client_id)?;

    Ok((
        DesktopWebLoginStart { login_url },
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
