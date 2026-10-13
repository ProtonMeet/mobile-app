use proton_meet_macro::async_trait_with_mock;

use crate::{
    domain::user::models::{UserTokenInfo, meeting_link_name::MeetingLinkName},
    errors::core::MeetCoreError,
};

#[async_trait_with_mock]
pub trait NewUserService {
    async fn join_room_with_switch_join_type(
        &self,
        user_info_token: &UserTokenInfo,
        meeting_link_name: &MeetingLinkName,
        switch_join_type: bool,
        is_waiting_room: bool,
    ) -> Result<(), MeetCoreError>;
}
