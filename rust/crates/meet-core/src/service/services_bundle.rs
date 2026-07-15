use std::sync::Arc;

use crate::domain::room::{RoomService, WaitingRoomService};

/// Services bundle for the meet application
///  will use in the future to bundle all services together during refactor
#[allow(unused)]
pub struct ServicesBundle {
    pub room_service: Arc<RoomService>,
    pub waiting_room_service: Arc<WaitingRoomService>,
    // pub message_service: Arc<MessageService>,
    // pub user_service: Arc<UserService>,
    // pub mls_service: Arc<MlsService>,
    // pub state_service: Arc<StateService>,
}

impl ServicesBundle {
    #[allow(unused)]
    pub(crate) fn new(
        room_service: Arc<RoomService>,
        waiting_room_service: Arc<WaitingRoomService>,
        // message_service: Arc<MessageService>,
        // user_service: Arc<UserService>,
        // mls_service: Arc<MlsService>,
        // state_service: Arc<StateService>,
    ) -> Self {
        Self {
            room_service,
            waiting_room_service,
        }
    }
}
