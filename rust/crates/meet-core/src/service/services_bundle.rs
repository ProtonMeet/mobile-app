use std::sync::Arc;

use crate::domain::room::RoomService;

/// Services bundle for the meet application
///  will use in the future to bundle all services together during refactor
#[allow(unused)]
pub struct ServicesBundle {
    pub room_service: Arc<RoomService>,
    // pub message_service: Arc<MessageService>,
    // pub user_service: Arc<UserService>,
    // pub mls_service: Arc<MlsService>,
    // pub state_service: Arc<StateService>,
}

impl ServicesBundle {
    #[allow(unused)]
    pub(crate) fn new(
        room_service: Arc<RoomService>,
        // message_service: Arc<MessageService>,
        // user_service: Arc<UserService>,
        // mls_service: Arc<MlsService>,
        // state_service: Arc<StateService>,
    ) -> Self {
        Self { room_service }
    }
}
