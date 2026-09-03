use std::sync::Arc;

use tokio::sync::RwLock;

#[cfg(not(target_family = "wasm"))]
use crate::service::auth::ArcAuthService;
use crate::{
    domain::room::{RoomService, WaitingRoomService},
    service::{agent::ArcAgentService, user_service::Service},
};

/// Services bundle for the meet application
pub(crate) struct ServicesBundle {
    pub room_service: Arc<RoomService>,
    pub waiting_room_service: Arc<WaitingRoomService>,
    #[cfg(not(target_family = "wasm"))]
    pub auth_service: ArcAuthService,
    pub agent_service: ArcAgentService,
    pub user_service: Arc<RwLock<Service>>,
}

impl ServicesBundle {
    pub(crate) fn new(
        room_service: Arc<RoomService>,
        waiting_room_service: Arc<WaitingRoomService>,
        #[cfg(not(target_family = "wasm"))] auth_service: ArcAuthService,
        agent_service: ArcAgentService,
        user_service: Arc<RwLock<Service>>,
    ) -> Self {
        Self {
            room_service,
            waiting_room_service,
            #[cfg(not(target_family = "wasm"))]
            auth_service,
            agent_service,
            user_service,
        }
    }
}
