use super::App;
use crate::domain::user::models::meeting_link_name::MeetingLinkName;
use crate::errors::core::MeetCoreError;

impl App {
    fn parse_meeting_link_name(s: &str) -> Result<MeetingLinkName, MeetCoreError> {
        MeetingLinkName::try_from(s).map_err(|_| MeetCoreError::InvalidInput {
            field: "meeting_link_name".to_string(),
            reason: "invalid meeting link name".to_string(),
        })
    }

    pub async fn admit_agent(
        &self,
        meeting_link_name: String,
        agent_device_id: String,
        meeting_password: String,
    ) -> Result<(), MeetCoreError> {
        let user_id = self.active_user_id().await?;
        let meeting = Self::parse_meeting_link_name(&meeting_link_name)?;
        self.user_service
            .read()
            .await
            .admit_agent(&meeting, &user_id, agent_device_id, meeting_password)
            .await
            .map_err(MeetCoreError::from)
    }

    pub async fn remove_agent(
        &self,
        meeting_link_name: String,
        agent_device_id: String,
    ) -> Result<(), MeetCoreError> {
        let user_id = self.active_user_id().await?;
        let meeting = Self::parse_meeting_link_name(&meeting_link_name)?;
        self.user_service
            .read()
            .await
            .remove_agent(&meeting, &user_id, agent_device_id)
            .await
            .map_err(MeetCoreError::from)
    }

    pub async fn list_pending_agents(
        &self,
        meeting_link_name: String,
    ) -> Result<Vec<String>, MeetCoreError> {
        let user_id = self.active_user_id().await?;
        // Validate the link name even though the server scopes the listing by
        // the host's session rather than by an explicit meeting parameter.
        Self::parse_meeting_link_name(&meeting_link_name)?;
        self.user_service
            .read()
            .await
            .list_pending_agents(&user_id)
            .await
            .map_err(MeetCoreError::from)
    }
}
