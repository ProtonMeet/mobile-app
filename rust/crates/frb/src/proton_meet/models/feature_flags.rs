pub struct FeatureFlags {
    pub use_message_queues: bool,
}

impl From<FeatureFlags> for proton_meet_core::domain::unleash::FeatureFlags {
    fn from(value: FeatureFlags) -> Self {
        Self::new(value.use_message_queues)
    }
}
