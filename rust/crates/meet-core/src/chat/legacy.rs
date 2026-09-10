use crate::app::{App, DecryptedMessageInfo};
use crate::domain::user::ports::UserService;
use crate::errors::core::MeetCoreError;
use mls_rs_codec::MlsEncode;
use mls_types::MlsMessage;

pub async fn encrypt_legacy(app: &App, message: &str) -> Result<Vec<u8>, MeetCoreError> {
    let meeting_id = app.active_meeting_link().await?;
    let encrypted_message = app
        .services
        .user_service
        .read()
        .await
        .encrypt_application_message(meeting_id.as_str(), message)
        .await?;
    Ok(encrypted_message.mls_encode_to_vec()?)
}

pub async fn decrypt_legacy(
    app: &App,
    data: Vec<u8>,
) -> Result<DecryptedMessageInfo, MeetCoreError> {
    let meeting_id = app.active_meeting_link().await?;
    let mls_message = MlsMessage::from_bytes(&data)?;
    let (decrypted_message, sender_id) = app
        .services
        .user_service
        .read()
        .await
        .decrypt_application_message(meeting_id.as_str(), mls_message)
        .await?;
    Ok(DecryptedMessageInfo {
        message: decrypted_message,
        sender_participant_id: sender_id.to_string(),
    })
}
