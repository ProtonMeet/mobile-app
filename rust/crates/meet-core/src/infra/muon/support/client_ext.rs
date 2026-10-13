//! Extension trait for [`MeetClient`] session helpers.

use proton_meet_macro::{async_trait, async_trait_with_mock};

use super::{MUON_DEFAULT_SESSION_KEY, MeetClient, MeetSession};

/// Meet-specific helpers on [`MeetClient`].
#[async_trait_with_mock]
pub trait MeetClientExt {
    /// Return the default Meet session, creating an unauthenticated one if needed.
    async fn default_session(&self) -> muon::Result<MeetSession>;
}

#[async_trait]
impl MeetClientExt for MeetClient {
    async fn default_session(&self) -> muon::Result<MeetSession> {
        if let Some(session) = self.get_session(MUON_DEFAULT_SESSION_KEY).await {
            return Ok(session);
        }
        self.new_session_without_credentials(MUON_DEFAULT_SESSION_KEY)
            .await
    }
}
