use crate::service::user_service::{
    utils::{group_has_agent, stagger_then_check_agent, StaggerOutcome},
    Service,
};

impl Service {
    /// True while a captions agent holds a leaf in the group. This is what the
    /// stagger below treats as "somebody already asked", so it doubles as the
    /// answer to whether there is anything left to do.
    pub(super) async fn captions_agent_in_group(&self, room_id: &str) -> bool {
        let store_lock = self.mls_store.read().await;
        match store_lock.group_map.get(room_id) {
            Some(group_arc) => {
                let mls_group = group_arc.read().await;
                group_has_agent(&mls_group)
            }
            None => false,
        }
    }

    /// Ask meet-server for the live-captions agent.
    ///
    /// Every participant that wants captions can call this. The rank-staggered
    /// wait means the request is normally made once, by the lowest-ranked
    /// participant, and the others take over in turn if the agent never turns
    /// up — so a wedged or slow participant can't keep captions from starting.
    /// Whether captions are wanted at all stays with the caller.
    pub async fn request_closed_captions(
        &self,
        meeting_link_name: &crate::domain::user::models::meeting_link_name::MeetingLinkName,
    ) -> Result<(), anyhow::Error> {
        self.settle_closed_captions(meeting_link_name, true).await
    }

    /// Ask meet-server to drop the live-captions agent, arbitrated the same way
    /// as [`Service::request_closed_captions`].
    pub async fn stop_closed_captions(
        &self,
        meeting_link_name: &crate::domain::user::models::meeting_link_name::MeetingLinkName,
    ) -> Result<(), anyhow::Error> {
        self.settle_closed_captions(meeting_link_name, false).await
    }

    async fn settle_closed_captions(
        &self,
        meeting_link_name: &crate::domain::user::models::meeting_link_name::MeetingLinkName,
        want_agent: bool,
    ) -> Result<(), anyhow::Error> {
        let room_id = meeting_link_name.as_str().to_string();
        let op_name = if want_agent {
            "request_closed_captions"
        } else {
            "stop_closed_captions"
        };

        let agent_in_group = self.captions_agent_in_group(&room_id).await;

        if want_agent && agent_in_group {
            self.state
                .lock()
                .await
                .set_awaiting_captions_agent(&room_id, false);
            tracing::info!(op = op_name, "agent already in the group, skipping");
            return Ok(());
        }

        if !want_agent && !agent_in_group {
            // An agent we asked for that hasn't turned up yet is invisible to
            // everyone else, so cancelling it is ours to do, and without the
            // wait: staggering would only let the agent join a meeting nobody
            // wants it in.
            if self.state.lock().await.is_awaiting_captions_agent(&room_id) {
                self.meeting_api
                    .remove_closed_captions_agent(&room_id)
                    .await?;
                self.state
                    .lock()
                    .await
                    .set_awaiting_captions_agent(&room_id, false);
                tracing::info!(op = op_name, "cancelled our own request");
            } else {
                tracing::info!(op = op_name, "no agent to remove, skipping");
            }

            return Ok(());
        }

        let group_arc = {
            let store_lock = self.mls_store.read().await;
            store_lock
                .group_map
                .get(&room_id)
                .ok_or_else(|| anyhow::anyhow!("group not loaded for meeting"))?
                .clone()
        };
        let rank = {
            let mls_group = group_arc.read().await;
            self.committer_rank(&mls_group).await?.1
        };

        if let StaggerOutcome::HandledElsewhere =
            stagger_then_check_agent(self, &room_id, rank, want_agent, op_name).await
        {
            return Ok(());
        }

        if want_agent {
            self.meeting_api.add_closed_captions_agent(&room_id).await?;
        } else {
            self.meeting_api
                .remove_closed_captions_agent(&room_id)
                .await?;
        }
        self.state
            .lock()
            .await
            .set_awaiting_captions_agent(&room_id, want_agent);
        tracing::info!(op = op_name, rank, "asked meet-server");

        Ok(())
    }

    pub async fn set_closed_captions_availability_as_host(
        &self,
        meeting_link_name: &crate::domain::user::models::meeting_link_name::MeetingLinkName,
        available: bool,
    ) -> Result<(), anyhow::Error> {
        let room_id = meeting_link_name.as_str().to_string();
        self.meeting_api
            .set_closed_captions_agent_availability(&room_id, available)
            .await?;
        Ok(())
    }
}
