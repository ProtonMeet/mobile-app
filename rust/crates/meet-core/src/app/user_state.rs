use super::App;
use crate::app_state::{preferred_user_key_for_crypto, UserState, UserStateInfo};
use crate::errors::core::MeetCoreError;

impl App {
    fn user_state_info_from(user_state: &UserState) -> Result<UserStateInfo, MeetCoreError> {
        let active_user_key = preferred_user_key_for_crypto(&user_state.user_keys)
            .ok_or(MeetCoreError::NoUserKeys)?
            .clone();
        let user_id = user_state.user_data.id.clone();
        let primary_address = user_state
            .user_addresses
            .first()
            .ok_or(MeetCoreError::NoPrimaryAddress)?
            .clone();

        Ok(UserStateInfo {
            active_user_key,
            user_id,
            primary_address,
        })
    }

    /// Extracts user authentication information from the active user state.
    pub(crate) async fn get_user_state_info(&self) -> Result<UserStateInfo, MeetCoreError> {
        let app_state = self.state.read().await;
        let user_state = app_state
            .active_user
            .as_ref()
            .ok_or(MeetCoreError::NoActiveUser)?;
        Self::user_state_info_from(user_state)
    }
}
