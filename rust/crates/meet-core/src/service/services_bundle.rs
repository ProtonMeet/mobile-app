use std::sync::Arc;

use tokio::sync::RwLock;

#[cfg(not(target_family = "wasm"))]
use crate::service::auth::ArcAuthService;
use crate::{
    domain::room::{RoomService, WaitingRoomService},
    service::{caption::ArcCaptionService, user_service::Service},
};

/// Services bundle for the meet application
pub(crate) struct ServiceBundle {
    pub room_service: Arc<RoomService>,
    pub waiting_room_service: Arc<WaitingRoomService>,
    #[cfg(not(target_family = "wasm"))]
    pub auth_service: ArcAuthService,
    pub caption_service: ArcCaptionService,
    pub user_service: Arc<RwLock<Service>>,
}

impl ServiceBundle {
    pub(crate) fn new(
        room_service: Arc<RoomService>,
        waiting_room_service: Arc<WaitingRoomService>,
        #[cfg(not(target_family = "wasm"))] auth_service: ArcAuthService,
        caption_service: ArcCaptionService,
        user_service: Arc<RwLock<Service>>,
    ) -> Self {
        Self {
            room_service,
            waiting_room_service,
            #[cfg(not(target_family = "wasm"))]
            auth_service,
            caption_service,
            user_service,
        }
    }

    pub async fn reset(&self) {
        tracing::info!("[WS-HANG] services_bundle.reset: acquiring user_service lock");
        let user_service_lock = self.user_service.write().await;
        tracing::info!("[WS-HANG] services_bundle.reset: user_service lock acquired");
        self.caption_service.reset().await;
        tracing::info!("[WS-HANG] services_bundle.reset: caption reset done");
        user_service_lock.reset_service_state().await;
        tracing::info!("[WS-HANG] services_bundle.reset: reset_service_state done");
    }
}
