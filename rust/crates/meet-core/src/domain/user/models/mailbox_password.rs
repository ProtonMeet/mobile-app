use proton_meet_crypto::MeetCrypto;

use crate::{errors::login::LoginError, infra::dto::proton_user::UserData};

/// Helper function to compute mailbox password from user data and password
pub async fn compute_mailbox_password(
    user_data: &UserData,
    password: &str,
) -> Result<String, LoginError> {
    let user_key = user_data
        .user
        .keys
        .as_ref()
        .and_then(|keys| keys.first())
        .ok_or(LoginError::NoUserKeys)?;

    let encoded_salt = user_data
        .key_salts
        .iter()
        .find(|key_salt| key_salt.id == user_key.id)
        .ok_or(LoginError::NoKeySalt)?
        .key_salt
        .as_ref()
        .ok_or(LoginError::NoKeySalt)?;

    Ok(MeetCrypto::compute_key_password(password, encoded_salt).await?)
}
