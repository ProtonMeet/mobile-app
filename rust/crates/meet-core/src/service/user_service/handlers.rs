use crate::{
    domain::room::JoinRequestChange,
    service::{service_state::MlsSyncState, user_service::GroupKeyUpdateReason},
};
use meet_type::RejoinReason;
use std::{future::Future, sync::Arc};
use tokio::sync::Mutex;

macro_rules! gen_set_clear {
    ($name:ident, ($($arg:ident: $t:ty),*), noclear) => {
        paste::paste! {
            #[cfg(not(target_family = "wasm"))]
            pub fn [<set_ $name>]<F, Fut>(&mut self, callback: F)
            where
                F: Fn($($t),*) -> Fut + Send + 'static,
                Fut: Future<Output = ()> + Unpin + Send + 'static,
            {
                tracing::info!(concat!("Service set ", stringify!($name)));
                self.$name = Some(Arc::new(Mutex::new(Box::new({
                    move |$($arg:$t),*| Box::new(callback($($arg),*))
                            as Box<dyn Future<Output = ()> + Send + Unpin>
                    }))))
            }

            #[cfg(target_family = "wasm")]
            pub fn [<set_ $name>]<F, Fut>(&mut self, callback: F)
            where
                F: Fn($($t),*) -> Fut + 'static,
                Fut: Future<Output = ()> + Unpin + 'static,
            {
                self.$name = Some(Arc::new(Mutex::new(Box::new({
                    move |$($arg:$t),*| {
                        Box::new(callback($($arg),*)) as Box<dyn Future<Output = ()> + Unpin>
                    }
                }))));
            }

            pub fn [<has_ $name>](&self) -> bool {
                self.$name.is_some()
            }

            #[allow(unused)]
            #[doc = "Calls the "]
            #[doc = stringify!($name)]
            #[doc = " handler with the provided arguments, returning `false` if it is not set."]
            pub async fn [<call_ $name>](&self, $($arg: $t),*) -> bool {
                let Some(handler) = self.$name.as_ref() else { return false };

                let mut handler = handler.lock().await;
                handler($($arg),*).await;

                true
            }

            #[allow(unused)]
            #[doc = "Calls the "]
            #[doc = stringify!($name)]
            #[doc = " handler with the provided arguments in a detached future using [`spawn_detached`][crate::utils::spawn_detached], returning `false` if it is not set."]
            pub fn [<call_detached_ $name>](&self, $($arg: $t),*) -> bool {
                let Some(handler) = self.$name.as_ref() else { return false };

                let handler = Arc::clone(handler);
                crate::utils::spawn_detached(async move {
                    let mut handler = handler.lock().await;
                    handler($($arg),*);
                });

                true
            }
        }
    };
    ($name:ident, ($($arg:ident: $t:ty),*)) => {
        gen_set_clear!($name, ($($arg:$t),*), noclear);

        paste::paste! {
            pub fn [<clear_ $name>](&mut self) {
                self.$name = None;
            }
        }
    };
}

macro_rules! gen_handlers {
    ($struct_name:ident, $(($handler_name:ident: $handler_type:ident, ($($arg:ident: $t:ty),*)$(, $clear:tt)?)),* ) => {
        $(
            #[cfg(not(target_family = "wasm"))]
            pub type $handler_type = Box<dyn FnMut($($t),*) -> Box<dyn Future<Output = ()> + Unpin + Send> + Send + 'static>;

            #[cfg(target_family = "wasm")]
            pub type $handler_type = Box<dyn FnMut($($t),*) -> Box<dyn Future<Output = ()> + Unpin> + 'static>;
        )*

        impl $struct_name {
            $(gen_set_clear!($handler_name, ($($arg: $t),*)$(, $clear)?);)*
        }
    };
}

#[derive(Clone, Default)]
pub struct Handlers {
    join_decision_handler: Option<Arc<Mutex<JoinDecisionHandler>>>,
    join_request_handler: Option<Arc<Mutex<JoinRequestHandler>>>,
    mls_group_update_handler: Option<Arc<Mutex<MlsGroupUpdateHandler>>>,
    mls_sync_state_update_handler: Option<Arc<Mutex<MlsSyncStateUpdateHandler>>>,
    agent_left_handler: Option<Arc<Mutex<AgentLeftHandler>>>,
    agent_pending_handler: Option<Arc<Mutex<AgentPendingHandler>>>,
    livekit_admin_change_handler: Option<Arc<Mutex<LiveKitAdminChangeHandler>>>,
}

gen_handlers! { Handlers,
    (join_decision_handler: JoinDecisionHandler, (request_id: String, admitted: bool)),
    (join_request_handler: JoinRequestHandler, (change: JoinRequestChange, request_id: String, participant_uid: String, expires_at: u64)),
    (mls_group_update_handler: MlsGroupUpdateHandler, (room_id: String, reason: GroupKeyUpdateReason), noclear),
    (mls_sync_state_update_handler: MlsSyncStateUpdateHandler , (state: MlsSyncState, reason: Option<RejoinReason>), noclear),
    (agent_left_handler: AgentLeftHandler, (device_id: String), noclear),
    (agent_pending_handler: AgentPendingHandler, (device_id: String), noclear),
    (livekit_admin_change_handler: LiveKitAdminChangeHandler, (room_id: String, participant_uid: String, participant_type: u32), noclear)
}
