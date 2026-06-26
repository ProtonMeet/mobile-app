use proton_meet_macro::async_trait_with_mock;

use crate::{
    domain::user::models::{meeting_link_name::MeetingLinkName, UserTokenInfo},
    errors::core::MeetCoreError,
};

#[async_trait_with_mock]
pub trait NewUserService {
    async fn join_room_with_switch_join_type(
        &self,
        user_info_token: &UserTokenInfo,
        meeting_link_name: &MeetingLinkName,
        switch_join_type: bool,
    ) -> Result<(), MeetCoreError>;
}
