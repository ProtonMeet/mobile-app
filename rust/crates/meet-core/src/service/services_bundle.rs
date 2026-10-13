use std::sync::Arc;

use tokio::sync::RwLock;

#[cfg(not(target_family = "wasm"))]
use crate::service::auth::ArcAuthService;
use crate::{
    domain::room::{RoomService, WaitingRoomService},
    service::{
        caption::ArcCaptionService, message_queue::ArcMessageQueueService, user_service::Service,
    },
};

/// Services bundle for the meet application
pub(crate) struct ServiceBundle {
    pub room_service: Arc<RoomService>,
    pub waiting_room_service: Arc<WaitingRoomService>,
    #[cfg(not(target_family = "wasm"))]
    pub auth_service: ArcAuthService,
    pub caption_service: ArcCaptionService,
    pub user_service: Arc<RwLock<Service>>,
    pub msg_queue_service: ArcMessageQueueService,
}

impl ServiceBundle {
    pub(crate) fn new(
        room_service: Arc<RoomService>,
        waiting_room_service: Arc<WaitingRoomService>,
        #[cfg(not(target_family = "wasm"))] auth_service: ArcAuthService,
        caption_service: ArcCaptionService,
        msg_queue_service: ArcMessageQueueService,
        user_service: Arc<RwLock<Service>>,
    ) -> Self {
        Self {
            room_service,
            waiting_room_service,
            #[cfg(not(target_family = "wasm"))]
            auth_service,
            caption_service,
            user_service,
            msg_queue_service,
        }
    }

    pub async fn reset(&self) {
        let user_service_lock = self.user_service.write().await;
        self.caption_service.reset().await;
        user_service_lock.reset_service_state().await;
    }
}
