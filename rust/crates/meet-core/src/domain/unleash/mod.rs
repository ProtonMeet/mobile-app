use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

/// Unleash-driven toggles consumed by the core.
///
/// Clones share the same underlying state, so a value set through [`App`](crate::app::App)
/// after construction is observed by every service holding a clone.
#[derive(Debug, Clone, Default)]
pub struct FeatureFlags {
    use_message_queues: Arc<AtomicBool>,
}

impl FeatureFlags {
    pub fn new(use_message_queues: bool) -> Self {
        Self {
            use_message_queues: Arc::new(AtomicBool::new(use_message_queues)),
        }
    }

    pub fn use_message_queues(&self) -> bool {
        self.use_message_queues.load(Ordering::Relaxed)
    }

    pub fn set_use_message_queues(&self, enabled: bool) {
        self.use_message_queues.store(enabled, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::FeatureFlags;

    #[test]
    fn default_disables_message_queues() {
        assert!(!FeatureFlags::default().use_message_queues());
    }

    #[test]
    fn clones_observe_updates() {
        let flags = FeatureFlags::new(false);
        let clone = flags.clone();

        flags.set_use_message_queues(true);
        assert!(clone.use_message_queues());

        clone.set_use_message_queues(false);
        assert!(!flags.use_message_queues());
    }
}
