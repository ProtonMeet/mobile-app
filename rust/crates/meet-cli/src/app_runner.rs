use std::sync::Arc;

use proton_meet_core::{
    app::App,
    infra::{auth_store::AuthStore, UserKeyProviderAdapter},
    muon::Auth,
};
use tokio::sync::Mutex;
use tracing::{error, info};

#[derive(Clone)]
pub struct AppRunner {
    pub app: App,
    pub display_name: String,
    pub room_name: String,
}

impl AppRunner {
    pub async fn prepare(
        api_host: String,
        ws_host: String,
        http_host: String,
        room_name: String,
        room_password: String,
        use_psk: bool,
        tag: Option<String>,
    ) -> Result<Self, anyhow::Error> {
        let auth = Arc::new(Mutex::new(Auth::None));
        let app = App::new(
            api_host.clone(),
            "macos-meet@0.0.1".to_string(),
            "Mozilla/5.0".to_string(),
            "test/db_path".to_string(),
            Box::new(AuthStore::from_custom_env_str(api_host.clone(), auth)),
            http_host,
            ws_host,
            None,
            Arc::new(UserKeyProviderAdapter::new()),
        )
        .await?;

        let display_name = match tag {
            Some(prefix) => format!("{}_{}", prefix, rand::random::<u32>()),
            None => format!("user_{}", rand::random::<u32>()),
        };
        info!("Authenticating meeting display name: {}", display_name);

        let meeting_info = app
            .authenticate_meeting_link(
                room_name.clone(),
                room_password.clone(),
                display_name.clone(),
            )
            .await?;

        #[cfg(debug_assertions)]
        info!("Meeting info: {:?}", meeting_info);

        app.join_meeting_with_access_token_with_proposal(
            meeting_info.access_token,
            room_name.clone(),
            room_password,
            use_psk,
            None,
        )
        .await?;
        // app.join_meeting_with_access_token(
        //     meeting_info.access_token,
        //     room_name.clone(),
        //     None, // TODO: use proton unauth session id
        // )
        // .await?;

        Ok(Self {
            app,
            display_name,
            room_name,
        })
    }

    pub async fn run_logic(&self) -> Result<(), anyhow::Error> {
        info!("[{}] Joined meeting", self.display_name);

        let app_clone = self.app.clone();
        let display_name = self.display_name.clone();

        self.app
            .set_mls_group_update_handler(move |room_id| {
                let app_inner = app_clone.clone();
                let tag = display_name.clone();
                Box::pin(async move {
                    tokio::spawn(async move {
                        #[cfg(debug_assertions)]
                        info!("[{}] Group key update triggered for room: {}", tag, room_id);
                        match app_inner.get_group_key().await {
                            Ok((group_key, epoch)) => {
                                #[cfg(debug_assertions)]
                                info!(
                                    "[{}] New Group key for room {}: {}, epoch: {}",
                                    tag, room_id, group_key, epoch
                                );
                            }
                            Err(e) => {
                                error!(
                                    "[{}] Failed to get group key for room {}: {}",
                                    tag, room_id, e
                                );
                            }
                        }
                    });
                })
            })
            .await;

        // let app_clone_for_admin = self.app.clone();
        let display_name_for_admin = self.display_name.clone();

        self.app
            .set_livekit_admin_change_handler(move |room_id, participant_uid, participant_type| {
                let tag = display_name_for_admin.clone();
                Box::pin(async move {
                    tokio::spawn(async move {
                        info!(
                            "[{}] LiveKit admin change triggered for room: {}, participant: {}, type: {}",
                            tag, room_id, participant_uid, participant_type
                        );
                    });
                })
            })
            .await;

        match self.app.get_group_key().await {
            Ok((group_key, epoch)) => {
                #[cfg(debug_assertions)]
                info!(
                    "[{}] Initial group key: {}, epoch: {}",
                    self.display_name, group_key, epoch
                );
            }
            Err(e) => {
                error!(
                    "[{}] Failed to get initial group key: {}",
                    self.display_name, e
                );
            }
        }

        tokio::time::sleep(std::time::Duration::from_secs(60)).await;
        Ok(())
    }

    pub async fn leave(&self) -> Result<(), anyhow::Error> {
        info!("[{}] Leaving room {}", self.display_name, self.room_name);
        self.app.leave_meeting().await?;
        Ok(())
    }
}
