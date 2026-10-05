use super::App;

impl App {
    pub fn set_use_cached_server_time(&self, enabled: bool) {
        if let Some(http) = &self.proton_http {
            http.server_time_tracker()
                .set_use_cached_server_time(enabled);
        }
    }

    /// Toggles the MLS message-queue path at runtime (driven by Unleash).
    pub fn set_use_message_queues(&self, enabled: bool) {
        self.feature_flags.set_use_message_queues(enabled);
    }
}
