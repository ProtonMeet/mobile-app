use std::sync::{Arc, Weak};

use tokio::sync::RwLock;

use crate::{
    domain::room::{RoomService, WaitingRoomService},
    service::{auth::AuthService, user_service::Service},
};

/// Services bundle for the meet application
pub struct ServicesBundle {
    pub room_service: RoomService,
    pub waiting_room_service: WaitingRoomService,
    pub auth_service: Box<dyn AuthService>,
    pub user_service: RwLock<Service>,
}

pub(crate) trait BundledService {
    fn set_service_bundle(&mut self, bundle: Weak<ServicesBundle>);
    fn services(&self) -> Result<Arc<ServicesBundle>, anyhow::Error>;
}

impl ServicesBundle {
    pub(crate) fn new(
        mut room_service: RoomService,
        mut waiting_room_service: WaitingRoomService,
        mut auth_service: Box<dyn AuthService>,
        user_service: RwLock<Service>,
    ) -> Arc<Self> {
        Arc::new_cyclic(|weak| {
            for service in [
                &mut room_service as &mut dyn BundledService,
                &mut waiting_room_service,
                auth_service.as_mut(),
            ] {
                service.set_service_bundle(weak.clone());
            }

            Self {
                room_service,
                waiting_room_service,
                auth_service,
                user_service,
            }
        })
    }
}
