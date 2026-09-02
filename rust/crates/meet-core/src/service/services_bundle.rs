use std::sync::Arc;

use tokio::sync::RwLock;

use crate::{
    domain::room::{RoomService, WaitingRoomService},
    service::{auth::ArcAuthService, user_service::Service},
};

/// Services bundle for the meet application
pub(crate) struct ServicesBundle {
    pub room_service: Arc<RoomService>,
    pub waiting_room_service: Arc<WaitingRoomService>,
    pub auth_service: ArcAuthService,
    pub user_service: RwLock<Service>,
}

impl ServicesBundle {
    pub(crate) fn new(
        room_service: Arc<RoomService>,
        waiting_room_service: Arc<WaitingRoomService>,
        auth_service: ArcAuthService,
        user_service: RwLock<Service>,
    ) -> Self {
        Self {
            room_service,
            waiting_room_service,
            auth_service,
            user_service,
        }
    }
}
