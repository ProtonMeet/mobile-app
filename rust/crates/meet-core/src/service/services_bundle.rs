use tokio::sync::RwLock;

use crate::{
    domain::room::{RoomService, WaitingRoomService},
    service::user_service::Service,
};

/// Services bundle for the meet application
///  will use in the future to bundle all services together during refactor
pub struct ServicesBundle {
    pub room_service: RoomService,
    pub waiting_room_service: WaitingRoomService,
    pub user_service: RwLock<Service>,
    // pub message_service: Arc<MessageService>,
    // pub user_service: Arc<UserService>,
    // pub mls_service: Arc<MlsService>,
    // pub state_service: Arc<StateService>,
}

impl ServicesBundle {
    pub fn new(
        room_service: RoomService,
        waiting_room_service: WaitingRoomService,
        user_service: RwLock<Service>,
        // message_service: Arc<MessageService>,
        // user_service: Arc<UserService>,
        // mls_service: Arc<MlsService>,
        // state_service: Arc<StateService>,
    ) -> Self {
        Self {
            room_service,
            waiting_room_service,
            user_service,
        }
    }
}
