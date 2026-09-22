use std::{
    collections::{hash_map::Entry, HashMap},
    future::Future,
    pin::Pin,
    sync::Arc,
};

use tokio::sync::RwLock;

#[cfg(not(target_family = "wasm"))]
use crate::service::auth::ArcAuthService;
use crate::{
    domain::room::{RoomService, WaitingRoomService},
    service::{caption::ArcCaptionService, message_queue::MessageQueue, user_service::Service},
    utils::sync::AsyncRwLock,
};

/// Services bundle for the meet application
pub(crate) struct ServiceBundle {
    pub room_service: Arc<RoomService>,
    pub waiting_room_service: Arc<WaitingRoomService>,
    #[cfg(not(target_family = "wasm"))]
    pub auth_service: ArcAuthService,
    pub caption_service: ArcCaptionService,
    pub user_service: Arc<RwLock<Service>>,
    pub mls_queues: AsyncRwLock<HashMap<String, Arc<MessageQueue>>>,
    queue_factory: Box<
        dyn Fn(String) -> Pin<Box<dyn Future<Output = Option<Arc<MessageQueue>>> + Send + Sync>>
            + Send
            + Sync,
    >,
}

impl ServiceBundle {
    pub(crate) fn new<
        F: Fn(String) -> Pin<Box<dyn Future<Output = Option<Arc<MessageQueue>>> + Send + Sync>>
            + Send
            + Sync
            + 'static,
    >(
        room_service: Arc<RoomService>,
        waiting_room_service: Arc<WaitingRoomService>,
        #[cfg(not(target_family = "wasm"))] auth_service: ArcAuthService,
        caption_service: ArcCaptionService,
        user_service: Arc<RwLock<Service>>,
        queue_factory: F,
    ) -> Self {
        Self {
            room_service,
            waiting_room_service,
            #[cfg(not(target_family = "wasm"))]
            auth_service,
            caption_service,
            user_service,
            mls_queues: AsyncRwLock::default(),
            queue_factory: Box::new(queue_factory),
        }
    }

    pub async fn reset(&self) {
        self.caption_service.reset().await;
    }

    pub async fn get_message_queue(
        &self,
        room_id: String,
    ) -> Result<Arc<MessageQueue>, anyhow::Error> {
        if let Some(queue) = self.mls_queues.read().await.get(&room_id) {
            return Ok(queue.clone());
        }

        let mut map = self.mls_queues.write_send().await;
        match map.entry(room_id.clone()) {
            Entry::Occupied(occupied_entry) => Ok(occupied_entry.get().clone()),
            Entry::Vacant(vacant_entry) => {
                let queue = (self.queue_factory)(room_id.clone())
                    .await
                    .ok_or_else(|| anyhow::anyhow!("Group for room {room_id} not found"))?;

                Ok(vacant_entry.insert_entry(queue).get().clone())
            }
        }
    }
}
