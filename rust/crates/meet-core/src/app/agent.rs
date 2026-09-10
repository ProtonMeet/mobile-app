use super::App;
use crate::domain::user::models::meeting_link_name::MeetingLinkName;
use crate::errors::core::MeetCoreError;

impl App {
    fn parse_meeting_link_name(s: &str) -> Result<MeetingLinkName, MeetCoreError> {
        Ok(MeetingLinkName::from(s))
    }

    pub async fn admit_agent(
        &self,
        meeting_link_name: String,
        agent_device_id: String,
        meeting_password: String,
    ) -> Result<(), MeetCoreError> {
        let user_id = self.active_user_id().await?;
        let meeting = Self::parse_meeting_link_name(&meeting_link_name)?;
        self.services
            .user_service
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
        self.services
            .user_service
            .read()
            .await
            .remove_agent(&meeting, &user_id, agent_device_id)
            .await
            .map_err(MeetCoreError::from)
    }

    /// Ask meet-server for the live-captions agent. Safe to call from every
    /// client that wants captions: the service arbitrates who actually asks.
    pub async fn request_closed_captions(
        &self,
        meeting_link_name: String,
    ) -> Result<(), MeetCoreError> {
        let meeting = Self::parse_meeting_link_name(&meeting_link_name)?;
        self.services
            .user_service
            .read()
            .await
            .request_closed_captions(&meeting)
            .await
            .map_err(MeetCoreError::from)
    }

    /// Ask meet-server to drop the live-captions agent, arbitrated the same way.
    pub async fn stop_closed_captions(
        &self,
        meeting_link_name: String,
    ) -> Result<(), MeetCoreError> {
        let meeting = Self::parse_meeting_link_name(&meeting_link_name)?;
        self.services
            .user_service
            .read()
            .await
            .stop_closed_captions(&meeting)
            .await
            .map_err(MeetCoreError::from)
    }

    pub async fn set_closed_captions_availability_as_host(
        &self,
        meeting_link_name: String,
        available: bool,
    ) -> Result<(), MeetCoreError> {
        let meeting = Self::parse_meeting_link_name(&meeting_link_name)?;
        self.services
            .user_service
            .read()
            .await
            .set_closed_captions_availability_as_host(&meeting, available)
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
        self.services
            .user_service
            .read()
            .await
            .list_pending_agents(&user_id)
            .await
            .map_err(MeetCoreError::from)
    }
}
