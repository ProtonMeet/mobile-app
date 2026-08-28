use std::sync::{Arc, Weak};

use tokio::sync::RwLock;

use crate::{
    domain::room::{RoomService, WaitingRoomService},
    service::user_service::Service,
};

/// Services bundle for the meet application
pub struct ServicesBundle {
    pub room_service: RoomService,
    pub waiting_room_service: WaitingRoomService,
    pub user_service: RwLock<Service>,
}

pub(crate) trait BundledService {
    fn set_service_bundle(&mut self, bundle: Weak<ServicesBundle>);
    fn services(&self) -> Result<Arc<ServicesBundle>, anyhow::Error>;
}

macro_rules! derive_bundled_service {
    ($s:ty, $f:ident) => {
        impl crate::service::services_bundle::BundledService for $s {
            fn set_service_bundle(
                &mut self,
                bundle: std::sync::Weak<crate::service::services_bundle::ServicesBundle>,
            ) {
                self.$f = bundle;
            }

            fn services(
                &self,
            ) -> Result<
                std::sync::Arc<crate::service::services_bundle::ServicesBundle>,
                anyhow::Error,
            > {
                self.$f
                    .upgrade()
                    .ok_or_else(|| anyhow::anyhow!("Service bundle is no longer available"))
            }
        }
    };
}

pub(crate) use derive_bundled_service;

impl ServicesBundle {
    pub fn new(
        room_service: RoomService,
        waiting_room_service: WaitingRoomService,
        user_service: RwLock<Service>,
    ) -> Arc<Self> {
        let mut bundle = Arc::new(Self {
            room_service,
            waiting_room_service,
            user_service,
        });

        let weak = Arc::downgrade(&bundle);
        let bundle_mut = Arc::get_mut(&mut bundle).unwrap();

        for service in [
            &mut bundle_mut.room_service as &mut dyn BundledService,
            &mut bundle_mut.waiting_room_service,
        ] {
            service.set_service_bundle(weak.clone());
        }

        bundle
    }
}
