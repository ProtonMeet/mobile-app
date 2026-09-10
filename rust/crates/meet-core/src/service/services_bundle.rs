use std::sync::Arc;

use tokio::sync::RwLock;

use crate::{
    domain::room::{RoomService, WaitingRoomService},
    service::user_service::Service,
};

/// Services bundle for the meet application
pub struct ServiceBundle {
    pub room_service: Arc<RoomService>,
    pub waiting_room_service: Arc<WaitingRoomService>,
    pub user_service: RwLock<Service>,
}

impl ServiceBundle {
    pub(crate) fn new(
        room_service: Arc<RoomService>,
        waiting_room_service: Arc<WaitingRoomService>,
        user_service: RwLock<Service>,
    ) -> Self {
        Self {
            room_service,
            waiting_room_service,
            user_service,
        }
    }
}
