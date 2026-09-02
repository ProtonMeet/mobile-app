use crate::{
    domain::room::JoinRequestChange,
    service::{service_state::MlsSyncState, user_service::GroupKeyUpdateReason},
};
use meet_type::RejoinReason;
use std::{future::Future, sync::Arc};
use tokio::sync::Mutex;

macro_rules! gen_handler_methods {
    ($name:ident, ($($arg:ident: $t:ty),*), detached_only=$do:tt, no_clear=true) => {
        paste::paste! {
            #[cfg(not(target_family = "wasm"))]
            pub fn [<set_ $name>]<F, Fut>(&mut self, mut callback: F)
            where
                F: FnMut($($t),*) -> Fut + Send + 'static,
                Fut: Future<Output = ()> + Unpin + Send + 'static,
            {
                tracing::info!(concat!("Service set ", stringify!($name)));
                self.$name = Some(Arc::new(Mutex::new(Box::new({
                    move |$($arg:$t),*| Box::new(callback($($arg),*))
                            as Box<dyn Future<Output = ()> + Send + Unpin>
                    }))))
            }

            #[cfg(target_family = "wasm")]
            pub fn [<set_ $name>]<F, Fut>(&mut self, mut callback: F)
            where
                F: FnMut($($t),*) -> Fut + 'static,
                Fut: Future<Output = ()> + Unpin + 'static,
            {
                self.$name = Some(Arc::new(Mutex::new(Box::new({
                    move |$($arg:$t),*| {
                        Box::new(callback($($arg),*)) as Box<dyn Future<Output = ()> + Unpin>
                    }
                }))));
            }

            #[allow(unused)]
            pub fn [<has_ $name>](&self) -> bool {
                self.$name.is_some()
            }

            gen_handler_methods!($name, ($($arg:$t),*), detached_only=$do);
        }
    };
    ($name:ident, ($($arg:ident: $t:ty),*), detached_only=$do:tt, no_clear=false) => {
        gen_handler_methods!($name, ($($arg:$t),*), detached_only=$do, no_clear=true);

        paste::paste! {
            pub fn [<clear_ $name>](&mut self) {
                self.$name = None;
            }
        }
    };
    ($name:ident, ($($arg:ident: $t:ty),*), detached_only=true) => {
        paste::paste! {
            #[allow(unused, non_camel_case_types)]
            #[doc = "Calls the "]
            #[doc = stringify!($name)]
            #[doc = " handler with the provided arguments in a detached future using [`spawn_detached`][crate::utils::spawn_detached], returning `false` if it is not set."]
            pub fn [<call_detached_ $name>](&self, $($arg: $t),*) -> bool {
                let Some(handler) = self.$name.as_ref() else { return false };

                let handler = Arc::clone(handler);

                crate::utils::spawn_detached(async move {
                    let mut handler = handler.lock().await;
                    handler($($arg),*).await;
                });

                true
            }
        }
    };
    ($name:ident, ($($arg:ident: $t:ty),*), detached_only=false) => {
        gen_handler_methods!($name, ($($arg:$t),*), detached_only=true);

        paste::paste! {
            #[allow(unused, non_camel_case_types)]
            #[doc = "Calls the "]
            #[doc = stringify!($name)]
            #[doc = " handler with the provided arguments, returning `false` if it is not set."]
            pub async fn [<call_ $name>](&self, $($arg: $t),*) -> bool {
                let Some(handler) = self.$name.as_ref() else { return false };

                let mut handler = handler.lock().await;
                handler($($arg),*).await;

                true
            }
        }
    };
}

macro_rules! gen_handlers {
    ($struct_name:ident, $(($handler_name:ident: $handler_type:ident, ($($arg:ident: $t:ty),*)$(, $param:tt=$val:tt)*)),* ) => {
        $(
            #[cfg(not(target_family = "wasm"))]
            pub type $handler_type = Box<dyn FnMut($($t),*) -> Box<dyn Future<Output = ()> + Unpin + Send> + Send + 'static>;

            #[cfg(target_family = "wasm")]
            pub type $handler_type = Box<dyn FnMut($($t),*) -> Box<dyn Future<Output = ()> + Unpin> + 'static>;
        )*

        impl $struct_name {
            $(gen_handler_methods!($handler_name, ($($arg: $t),*)$(, $param=$val)*);)*
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
    (join_decision_handler: JoinDecisionHandler, (request_id: String, admitted: bool), detached_only=true, no_clear=false),
    (join_request_handler: JoinRequestHandler, (change: JoinRequestChange, request_id: String, participant_uid: String, expires_at: u64), detached_only=true, no_clear=false),
    (mls_group_update_handler: MlsGroupUpdateHandler, (room_id: String, reason: GroupKeyUpdateReason), detached_only=false, no_clear=true),
    (mls_sync_state_update_handler: MlsSyncStateUpdateHandler, (state: MlsSyncState, reason: Option<RejoinReason>), detached_only=false, no_clear=true),
    (agent_left_handler: AgentLeftHandler, (device_id: String), detached_only=false, no_clear=true),
    (agent_pending_handler: AgentPendingHandler, (device_id: String), detached_only=false, no_clear=true),
    (livekit_admin_change_handler: LiveKitAdminChangeHandler, (room_id: String, participant_uid: String, participant_type: u32), detached_only=false, no_clear=true)
}

impl Handlers {
    pub fn new() -> Self {
        Self::default()
    }
}

#[cfg(test)]
mod tests {
    use std::{
        future::ready,
        sync::atomic::{AtomicBool, AtomicU8, Ordering},
        time::Duration,
    };

    use futures::FutureExt;
    use meet_type::RejoinReason;
    use tokio::time::sleep;

    use crate::{
        domain::room::JoinRequestChange,
        service::{
            service_state::MlsSyncState,
            user_service::{handlers::Handlers, GroupKeyUpdateReason},
        },
    };

    #[tokio::test]
    async fn test_call_mls_group_update_exactly_once() {
        let mut handlers = Handlers::new();

        static COUNTER: AtomicU8 = AtomicU8::new(0);

        handlers.set_mls_group_update_handler(|_, _| {
            COUNTER.fetch_add(1, Ordering::AcqRel);
            ready(()).boxed()
        });

        let called = handlers
            .call_mls_group_update_handler("".into(), GroupKeyUpdateReason::Join)
            .await;

        assert!(called);

        // Check that the handler was called exactly once.
        assert_eq!(COUNTER.load(Ordering::Acquire), 1);
    }

    #[test]
    fn test_has_handler() {
        let mut handlers = Handlers::new();
        assert!(!handlers.has_livekit_admin_change_handler());

        handlers.set_livekit_admin_change_handler(|_, _, _| ready(()).boxed());
        assert!(handlers.has_livekit_admin_change_handler());
    }

    #[test]
    fn test_clear_handler() {
        let mut handlers = Handlers::new();
        assert!(!handlers.has_join_decision_handler());

        handlers.set_join_decision_handler(|_, _| ready(()).boxed());
        assert!(handlers.has_join_decision_handler());

        handlers.clear_join_decision_handler();
        assert!(!handlers.has_join_decision_handler());
    }

    #[tokio::test]
    async fn test_all_handlers() {
        let mut handlers = Handlers::new();

        static JOIN_DECISION_HANDLER_CALLED: AtomicBool = AtomicBool::new(false);
        static JOIN_REQUEST_HANDLER_CALLED: AtomicBool = AtomicBool::new(false);
        static MLS_GROUP_UPDATE_HANDLER_CALLED: AtomicBool = AtomicBool::new(false);
        static MLS_SYNC_STATE_UPDATE_HANDLER_CALLED: AtomicBool = AtomicBool::new(false);
        static AGENT_LEFT_HANDLER_CALLED: AtomicBool = AtomicBool::new(false);
        static AGENT_PENDING_HANDLER_CALLED: AtomicBool = AtomicBool::new(false);
        static LIVEKIT_ADMIN_CHANGE_HANDLER_CALLED: AtomicBool = AtomicBool::new(false);

        fn check_called(should_be_true: &[&AtomicBool], should_be_false: &[&AtomicBool]) {
            for a in should_be_true {
                assert!(a.load(Ordering::SeqCst));
            }
            for a in should_be_false {
                assert!(!a.load(Ordering::SeqCst));
            }
        }

        handlers.set_join_decision_handler(|_, _| {
            JOIN_DECISION_HANDLER_CALLED.store(true, Ordering::Release);
            ready(()).boxed()
        });

        handlers.set_join_request_handler(|_, _, _, _| {
            JOIN_REQUEST_HANDLER_CALLED.store(true, Ordering::Release);
            ready(()).boxed()
        });

        handlers.set_mls_group_update_handler(|_, _| {
            MLS_GROUP_UPDATE_HANDLER_CALLED.store(true, Ordering::Release);
            ready(()).boxed()
        });

        handlers.set_mls_sync_state_update_handler(|_, _| {
            MLS_SYNC_STATE_UPDATE_HANDLER_CALLED.store(true, Ordering::Release);
            ready(()).boxed()
        });

        handlers.set_agent_left_handler(|_| {
            AGENT_LEFT_HANDLER_CALLED.store(true, Ordering::Release);
            ready(()).boxed()
        });

        handlers.set_agent_pending_handler(|_| {
            AGENT_PENDING_HANDLER_CALLED.store(true, Ordering::Release);
            ready(()).boxed()
        });

        handlers.set_livekit_admin_change_handler(|_, _, _| {
            LIVEKIT_ADMIN_CHANGE_HANDLER_CALLED.store(true, Ordering::Release);
            ready(()).boxed()
        });

        check_called(
            &[],
            &[
                &JOIN_DECISION_HANDLER_CALLED,
                &JOIN_REQUEST_HANDLER_CALLED,
                &MLS_GROUP_UPDATE_HANDLER_CALLED,
                &MLS_SYNC_STATE_UPDATE_HANDLER_CALLED,
                &AGENT_LEFT_HANDLER_CALLED,
                &AGENT_PENDING_HANDLER_CALLED,
                &LIVEKIT_ADMIN_CHANGE_HANDLER_CALLED,
            ],
        );

        handlers.call_detached_join_decision_handler("".into(), true);
        sleep(Duration::from_millis(50)).await;
        check_called(
            &[&JOIN_DECISION_HANDLER_CALLED],
            &[
                &JOIN_REQUEST_HANDLER_CALLED,
                &MLS_GROUP_UPDATE_HANDLER_CALLED,
                &MLS_SYNC_STATE_UPDATE_HANDLER_CALLED,
                &AGENT_LEFT_HANDLER_CALLED,
                &AGENT_PENDING_HANDLER_CALLED,
                &LIVEKIT_ADMIN_CHANGE_HANDLER_CALLED,
            ],
        );

        handlers.call_detached_join_request_handler(
            JoinRequestChange::Added,
            "".into(),
            "".into(),
            0u64,
        );
        sleep(Duration::from_millis(50)).await;
        check_called(
            &[&JOIN_DECISION_HANDLER_CALLED, &JOIN_REQUEST_HANDLER_CALLED],
            &[
                &MLS_GROUP_UPDATE_HANDLER_CALLED,
                &MLS_SYNC_STATE_UPDATE_HANDLER_CALLED,
                &AGENT_LEFT_HANDLER_CALLED,
                &AGENT_PENDING_HANDLER_CALLED,
                &LIVEKIT_ADMIN_CHANGE_HANDLER_CALLED,
            ],
        );

        handlers
            .call_mls_group_update_handler("".into(), GroupKeyUpdateReason::Join)
            .await;
        check_called(
            &[
                &JOIN_DECISION_HANDLER_CALLED,
                &JOIN_REQUEST_HANDLER_CALLED,
                &MLS_GROUP_UPDATE_HANDLER_CALLED,
            ],
            &[
                &MLS_SYNC_STATE_UPDATE_HANDLER_CALLED,
                &AGENT_LEFT_HANDLER_CALLED,
                &AGENT_PENDING_HANDLER_CALLED,
                &LIVEKIT_ADMIN_CHANGE_HANDLER_CALLED,
            ],
        );
        handlers
            .call_mls_sync_state_update_handler(
                MlsSyncState::Checking,
                Some(RejoinReason::EpochMismatch),
            )
            .await;
        check_called(
            &[
                &JOIN_DECISION_HANDLER_CALLED,
                &JOIN_REQUEST_HANDLER_CALLED,
                &MLS_GROUP_UPDATE_HANDLER_CALLED,
                &MLS_SYNC_STATE_UPDATE_HANDLER_CALLED,
            ],
            &[
                &AGENT_LEFT_HANDLER_CALLED,
                &AGENT_PENDING_HANDLER_CALLED,
                &LIVEKIT_ADMIN_CHANGE_HANDLER_CALLED,
            ],
        );

        handlers.call_agent_left_handler("".into()).await;
        check_called(
            &[
                &JOIN_DECISION_HANDLER_CALLED,
                &JOIN_REQUEST_HANDLER_CALLED,
                &MLS_GROUP_UPDATE_HANDLER_CALLED,
                &MLS_SYNC_STATE_UPDATE_HANDLER_CALLED,
                &AGENT_LEFT_HANDLER_CALLED,
            ],
            &[
                &AGENT_PENDING_HANDLER_CALLED,
                &LIVEKIT_ADMIN_CHANGE_HANDLER_CALLED,
            ],
        );

        handlers.call_agent_pending_handler("".into()).await;
        check_called(
            &[
                &JOIN_DECISION_HANDLER_CALLED,
                &JOIN_REQUEST_HANDLER_CALLED,
                &MLS_GROUP_UPDATE_HANDLER_CALLED,
                &MLS_SYNC_STATE_UPDATE_HANDLER_CALLED,
                &AGENT_LEFT_HANDLER_CALLED,
                &AGENT_PENDING_HANDLER_CALLED,
            ],
            &[&LIVEKIT_ADMIN_CHANGE_HANDLER_CALLED],
        );

        handlers
            .call_livekit_admin_change_handler("".into(), "".into(), 0u32)
            .await;
        check_called(
            &[
                &JOIN_DECISION_HANDLER_CALLED,
                &JOIN_REQUEST_HANDLER_CALLED,
                &MLS_GROUP_UPDATE_HANDLER_CALLED,
                &MLS_SYNC_STATE_UPDATE_HANDLER_CALLED,
                &AGENT_LEFT_HANDLER_CALLED,
                &AGENT_PENDING_HANDLER_CALLED,
                &LIVEKIT_ADMIN_CHANGE_HANDLER_CALLED,
            ],
            &[],
        );
    }
}
