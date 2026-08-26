use crate::service::user_service::Service;
use crate::{
    domain::room::JoinRequestChange,
    service::{service_state::MlsSyncState, user_service::GroupKeyUpdateReason},
};
use meet_type::RejoinReason;
use std::{future::Future, sync::Arc};
use tokio::sync::Mutex;

impl Service {
    #[cfg(not(target_family = "wasm"))]
    pub fn set_join_decision_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String, bool) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        tracing::info!("Service set join decision handler");
        self.join_decision_handler = Some(Arc::new(Mutex::new(Box::new({
            move |request_id, admitted| {
                Box::new(callback(request_id, admitted))
                    as Box<dyn Future<Output = ()> + Send + Unpin>
            }
        }))));
    }

    #[cfg(target_family = "wasm")]
    pub fn set_join_decision_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String, bool) -> Fut + 'static,
        Fut: Future<Output = ()> + Unpin + 'static,
    {
        self.join_decision_handler = Some(Arc::new(Mutex::new(Box::new({
            move |request_id, admitted| {
                Box::new(callback(request_id, admitted)) as Box<dyn Future<Output = ()> + Unpin>
            }
        }))));
    }

    pub fn clear_join_decision_handler(&mut self) {
        self.join_decision_handler = None;
    }

    #[cfg(not(target_family = "wasm"))]
    pub fn set_join_request_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(JoinRequestChange, String, String, u64) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        tracing::info!("Service set join request handler");
        self.join_request_handler = Some(Arc::new(Mutex::new(Box::new({
            move |change, request_id, participant_uid, expires_at| {
                Box::new(callback(change, request_id, participant_uid, expires_at))
                    as Box<dyn Future<Output = ()> + Send + Unpin>
            }
        }))));
    }

    #[cfg(target_family = "wasm")]
    pub fn set_join_request_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(JoinRequestChange, String, String, u64) -> Fut + 'static,
        Fut: Future<Output = ()> + Unpin + 'static,
    {
        self.join_request_handler = Some(Arc::new(Mutex::new(Box::new({
            move |change, request_id, participant_uid, expires_at| {
                Box::new(callback(change, request_id, participant_uid, expires_at))
                    as Box<dyn Future<Output = ()> + Unpin>
            }
        }))));
    }

    pub fn clear_join_request_handler(&mut self) {
        self.join_request_handler = None;
    }

    #[cfg(not(target_family = "wasm"))]
    pub fn set_mls_group_update_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String, GroupKeyUpdateReason) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        tracing::info!("Service set mls group update handler");
        self.mls_group_update_handler = Some(Arc::new(Mutex::new(Box::new({
            move |room_id, reason| {
                Box::new(callback(room_id, reason)) as Box<dyn Future<Output = ()> + Send + Unpin>
            }
        }))));
    }

    #[cfg(target_family = "wasm")]
    pub fn set_mls_group_update_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String, GroupKeyUpdateReason) -> Fut + 'static,
        Fut: Future<Output = ()> + Unpin + 'static,
    {
        self.mls_group_update_handler = Some(Arc::new(Mutex::new(Box::new({
            move |room_id, reason| {
                Box::new(callback(room_id, reason)) as Box<dyn Future<Output = ()> + Unpin>
            }
        }))));
    }

    #[cfg(not(target_family = "wasm"))]
    pub fn set_mls_sync_state_update_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(MlsSyncState, Option<RejoinReason>) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        tracing::info!("Service set mls sync state update handler");
        self.mls_sync_state_update_handler = Some(Arc::new(Mutex::new(Box::new({
            move |state, reason| {
                Box::new(callback(state, reason)) as Box<dyn Future<Output = ()> + Send + Unpin>
            }
        }))));
    }

    #[cfg(target_family = "wasm")]
    pub fn set_mls_sync_state_update_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(MlsSyncState, Option<RejoinReason>) -> Fut + 'static,
        Fut: Future<Output = ()> + Unpin + 'static,
    {
        self.mls_sync_state_update_handler = Some(Arc::new(Mutex::new(Box::new({
            move |state, reason| {
                Box::new(callback(state, reason)) as Box<dyn Future<Output = ()> + Unpin>
            }
        }))));
    }

    #[cfg(not(target_family = "wasm"))]
    pub fn set_agent_pending_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        tracing::info!("Service set agent pending handler");
        self.agent_pending_handler = Some(Arc::new(Mutex::new(Box::new({
            move |device_id| {
                Box::new(callback(device_id)) as Box<dyn Future<Output = ()> + Send + Unpin>
            }
        }))));
    }

    #[cfg(target_family = "wasm")]
    pub fn set_agent_pending_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String) -> Fut + 'static,
        Fut: Future<Output = ()> + Unpin + 'static,
    {
        self.agent_pending_handler = Some(Arc::new(Mutex::new(Box::new({
            move |device_id| Box::new(callback(device_id)) as Box<dyn Future<Output = ()> + Unpin>
        }))));
    }

    #[cfg(not(target_family = "wasm"))]
    pub fn set_agent_left_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        tracing::info!("Service set agent left handler");
        self.agent_left_handler = Some(Arc::new(Mutex::new(Box::new({
            move |device_id| {
                Box::new(callback(device_id)) as Box<dyn Future<Output = ()> + Send + Unpin>
            }
        }))));
    }

    #[cfg(target_family = "wasm")]
    pub fn set_agent_left_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String) -> Fut + 'static,
        Fut: Future<Output = ()> + Unpin + 'static,
    {
        self.agent_left_handler = Some(Arc::new(Mutex::new(Box::new({
            move |device_id| Box::new(callback(device_id)) as Box<dyn Future<Output = ()> + Unpin>
        }))));
    }

    #[cfg(not(target_family = "wasm"))]
    pub fn set_livekit_admin_change_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String, String, u32) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        tracing::info!("Service set livekit admin change handler");
        self.livekit_admin_change_handler = Some(Arc::new(Mutex::new(Box::new({
            move |room_id, participant_uid, participant_type| {
                Box::new(callback(room_id, participant_uid, participant_type))
                    as Box<dyn Future<Output = ()> + Send + Unpin>
            }
        }))));
    }

    #[cfg(target_family = "wasm")]
    pub fn set_livekit_admin_change_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String, String, u32) -> Fut + 'static,
        Fut: Future<Output = ()> + Unpin + 'static,
    {
        self.livekit_admin_change_handler = Some(Arc::new(Mutex::new(Box::new({
            move |room_id, participant_uid, participant_type| {
                Box::new(callback(room_id, participant_uid, participant_type))
                    as Box<dyn Future<Output = ()> + Unpin>
            }
        }))));
    }
}
