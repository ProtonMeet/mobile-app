use crate::utils::{PlatformInstant, instant};
use chrono::NaiveDateTime;
use std::{
    sync::{
        Arc, RwLock,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

/// Monotonic anchor for extrapolating server time between HTTP syncs.
#[derive(Clone, Debug)]
struct ServerTimeAnchor {
    /// Greatest valid server timestamp (whole seconds) at observation time.
    server_sec: i64,
    /// Monotonic instant when [`Self::server_sec`] was recorded.
    observed_at: PlatformInstant,
}

fn extrapolate(anchor: &ServerTimeAnchor) -> (i64, Duration) {
    let elapsed = anchor.observed_at.elapsed();
    let server_sec = anchor.server_sec.saturating_add(elapsed.as_secs() as i64);
    (server_sec, elapsed)
}

fn extrapolated_sec(anchor: &ServerTimeAnchor) -> i64 {
    extrapolate(anchor).0
}

fn extrapolated_duration(anchor: &ServerTimeAnchor) -> Duration {
    let (server_sec, elapsed) = extrapolate(anchor);
    Duration::new(server_sec.unsigned_abs(), elapsed.subsec_nanos())
}

fn should_update_anchor(anchor: Option<&ServerTimeAnchor>, timestamp_sec: i64) -> bool {
    match anchor {
        None => true,
        Some(current) => timestamp_sec > extrapolated_sec(current),
    }
}

/// Tracks the greatest valid server timestamp observed by a shared HTTP client and
/// extrapolates forward using a monotonic clock.
#[derive(Clone, Debug)]
pub(crate) struct ServerTimeTracker {
    anchor: Arc<RwLock<Option<ServerTimeAnchor>>>,
    use_cached_server_time: Arc<AtomicBool>,
}

impl Default for ServerTimeTracker {
    fn default() -> Self {
        Self {
            anchor: Arc::new(RwLock::new(None)),
            use_cached_server_time: Arc::new(AtomicBool::new(false)),
        }
    }
}

impl ServerTimeTracker {
    pub(crate) fn new() -> Self {
        Self::default()
    }

    fn with_anchor<T>(&self, f: impl FnOnce(&ServerTimeAnchor) -> T) -> Option<T> {
        self.anchor
            .read()
            .ok()
            .and_then(|stored| stored.as_ref().map(f))
    }

    pub(crate) fn set_use_cached_server_time(&self, enabled: bool) {
        self.use_cached_server_time
            .store(enabled, Ordering::Relaxed);
    }

    /// Observes response header values without allowing extrapolated server time to regress.
    ///
    /// A valid `x-pm-date` takes precedence over `Date`. Invalid headers are ignored
    /// because they must not affect the request that carried them. A new observation
    /// replaces the anchor only when its timestamp is strictly greater than the current
    /// extrapolated server time.
    pub(crate) fn observe_header_values(&self, x_pm_date: Option<&str>, date: Option<&str>) {
        let timestamp_sec = x_pm_date
            .and_then(parse_x_pm_date)
            .or_else(|| date.and_then(parse_http_date));

        let Some(timestamp_sec) = timestamp_sec else {
            tracing::debug!("Ignoring invalid server time response headers");
            return;
        };

        let Ok(mut stored) = self.anchor.write() else {
            tracing::debug!("Unable to update server time because its lock is poisoned");
            return;
        };

        if should_update_anchor(stored.as_ref(), timestamp_sec) {
            tracing::debug!("Updating server time anchor to {}", timestamp_sec);
            *stored = Some(ServerTimeAnchor {
                server_sec: timestamp_sec,
                observed_at: instant::now(),
            });
        }
    }

    /// Extrapolated server time in whole seconds since the Unix epoch.
    #[cfg_attr(not(test), expect(dead_code))]
    pub(crate) fn timestamp(&self) -> Option<i64> {
        self.with_anchor(extrapolated_sec)
    }

    /// Extrapolated server time as [`Duration`] since the Unix epoch, for MLS `artificial_time`.
    ///
    /// Returns `None` until a response has been observed, when cached server time is disabled
    /// via feature flag, or when callers should fall back to the local clock. Accuracy degrades
    /// over long gaps without HTTP sync or during device sleep when the monotonic clock pauses.
    pub(crate) fn server_time_as_duration(&self) -> Option<Duration> {
        if !self.use_cached_server_time.load(Ordering::Relaxed) {
            return None;
        }

        self.with_anchor(extrapolated_duration)
    }
}

fn parse_timestamp(value: &str, format: &str) -> Option<i64> {
    NaiveDateTime::parse_from_str(value.trim(), format)
        .ok()
        .map(|datetime| datetime.and_utc().timestamp())
}

fn parse_x_pm_date(value: &str) -> Option<i64> {
    parse_timestamp(value, "%d %b %Y %H:%M:%S GMT")
}

fn parse_http_date(value: &str) -> Option<i64> {
    parse_timestamp(value, "%a, %d %b %Y %H:%M:%S GMT")
}

#[cfg(test)]
mod tests {
    use super::*;

    const X_PM_DATE: &str = "17 Aug 2026 09:49:56 GMT";
    const HTTP_DATE: &str = "Mon, 17 Aug 2026 09:49:56 GMT";

    #[test]
    fn prefers_x_pm_date_when_both_headers_are_valid() {
        let tracker = ServerTimeTracker::new();

        tracker.observe_header_values(Some("17 Aug 2026 09:50:00 GMT"), Some(HTTP_DATE));

        assert_eq!(
            tracker.timestamp(),
            parse_x_pm_date("17 Aug 2026 09:50:00 GMT")
        );
    }

    #[test]
    fn falls_back_to_date_when_x_pm_date_is_missing_or_invalid() {
        let tracker = ServerTimeTracker::new();

        tracker.observe_header_values(None, Some(HTTP_DATE));
        assert!(tracker.timestamp().is_some());

        let expected = tracker.timestamp();
        tracker.observe_header_values(Some("not a date"), Some(HTTP_DATE));
        assert_eq!(tracker.timestamp(), expected);
    }

    #[test]
    fn ignores_missing_and_invalid_headers() {
        let tracker = ServerTimeTracker::new();

        tracker.observe_header_values(None, None);
        tracker.observe_header_values(Some("not a date"), Some("also not a date"));
        tracker.observe_header_values(None, Some("Mon, 17 Aug 2026 09:49:56 +0000"));

        assert_eq!(tracker.timestamp(), None);
    }

    #[test]
    fn never_regresses_the_observed_timestamp() {
        let tracker = ServerTimeTracker::new();

        tracker.observe_header_values(Some("17 Aug 2026 09:50:00 GMT"), None);
        let newest = tracker.timestamp();

        tracker.observe_header_values(Some(X_PM_DATE), None);
        assert_eq!(tracker.timestamp(), newest);

        tracker.observe_header_values(Some("17 Aug 2026 09:50:01 GMT"), None);
        assert!(tracker.timestamp() > newest);
    }

    #[test]
    fn returns_none_when_cached_server_time_is_disabled() {
        let tracker = ServerTimeTracker::new();

        tracker.observe_header_values(Some("17 Aug 2026 09:50:00 GMT"), None);
        tracker.set_use_cached_server_time(false);

        assert!(tracker.server_time_as_duration().is_none());
    }

    #[test]
    fn returns_cached_timestamp_when_cached_server_time_is_enabled() {
        let tracker = ServerTimeTracker::new();

        tracker.observe_header_values(Some("17 Aug 2026 09:50:00 GMT"), None);
        tracker.set_use_cached_server_time(true);

        assert!(tracker.server_time_as_duration().is_some());
    }

    #[test]
    fn propagates_cached_server_time_flag_across_clones() {
        let tracker = ServerTimeTracker::new();
        let clone = tracker.clone();

        tracker.observe_header_values(Some("17 Aug 2026 09:50:00 GMT"), None);
        tracker.set_use_cached_server_time(false);

        assert!(clone.server_time_as_duration().is_none());
    }

    #[test]
    fn extrapolates_forward_between_observations() {
        let tracker = ServerTimeTracker::new();

        tracker.observe_header_values(Some("17 Aug 2026 09:50:00 GMT"), None);
        tracker.set_use_cached_server_time(true);

        let first = tracker.server_time_as_duration().unwrap();
        std::thread::sleep(Duration::from_millis(10));
        let second = tracker.server_time_as_duration().unwrap();

        assert!(second > first);
    }

    #[test]
    fn does_not_regress_when_header_is_behind_extrapolated_time() {
        let tracker = ServerTimeTracker::new();

        tracker.observe_header_values(Some("17 Aug 2026 09:50:00 GMT"), None);
        std::thread::sleep(Duration::from_millis(10));
        let before = tracker.timestamp().unwrap();

        tracker.observe_header_values(Some(X_PM_DATE), None);

        assert_eq!(tracker.timestamp(), Some(before));
    }

    #[test]
    fn updates_anchor_when_header_jumps_ahead() {
        let tracker = ServerTimeTracker::new();

        tracker.observe_header_values(Some("17 Aug 2026 09:50:00 GMT"), None);
        tracker.observe_header_values(Some("17 Aug 2026 09:50:05 GMT"), None);

        assert_eq!(
            tracker.timestamp(),
            parse_x_pm_date("17 Aug 2026 09:50:05 GMT")
        );
    }

    #[test]
    fn includes_sub_second_precision_in_duration() {
        let tracker = ServerTimeTracker::new();

        tracker.observe_header_values(Some("17 Aug 2026 09:50:00 GMT"), None);
        tracker.set_use_cached_server_time(true);
        std::thread::sleep(Duration::from_millis(10));

        let duration = tracker.server_time_as_duration().unwrap();
        assert!(duration.subsec_nanos() > 0);
    }

    #[test]
    fn clone_shares_anchor_and_extrapolates() {
        let tracker = ServerTimeTracker::new();
        let clone = tracker.clone();

        tracker.observe_header_values(Some("17 Aug 2026 09:50:00 GMT"), None);
        tracker.set_use_cached_server_time(true);
        clone.set_use_cached_server_time(true);

        assert_eq!(tracker.timestamp(), clone.timestamp());
    }
}
