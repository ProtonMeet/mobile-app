use chrono::NaiveDateTime;
use std::sync::{Arc, RwLock};

/// Tracks the greatest valid server timestamp observed by a shared HTTP client.
#[derive(Clone, Debug, Default)]
pub(crate) struct ServerTimeTracker {
    timestamp_sec: Arc<RwLock<Option<i64>>>,
}

impl ServerTimeTracker {
    pub(crate) fn new() -> Self {
        Self::default()
    }

    /// Observes response header values without allowing the stored timestamp to regress.
    ///
    /// A valid `x-pm-date` takes precedence over `Date`. Invalid headers are ignored
    /// because they must not affect the request that carried them.
    pub(crate) fn observe_header_values(&self, x_pm_date: Option<&str>, date: Option<&str>) {
        let timestamp_sec = x_pm_date
            .and_then(parse_x_pm_date)
            .or_else(|| date.and_then(parse_http_date));

        let Some(timestamp_sec) = timestamp_sec else {
            tracing::debug!("Ignoring invalid server time response headers");
            return;
        };

        let Ok(mut stored) = self.timestamp_sec.write() else {
            tracing::debug!("Unable to update server time because its lock is poisoned");
            return;
        };

        if stored.is_none_or(|current| timestamp_sec > current) {
            tracing::debug!("Updating server time to {}", timestamp_sec);
            *stored = Some(timestamp_sec);
        }
    }

    pub(crate) fn timestamp(&self) -> Option<i64> {
        self.timestamp_sec.read().ok().and_then(|stored| *stored)
    }
}

fn parse_x_pm_date(value: &str) -> Option<i64> {
    NaiveDateTime::parse_from_str(value.trim(), "%d %b %Y %H:%M:%S GMT")
        .ok()
        .map(|datetime| datetime.and_utc().timestamp())
}

fn parse_http_date(value: &str) -> Option<i64> {
    NaiveDateTime::parse_from_str(value.trim(), "%a, %d %b %Y %H:%M:%S GMT")
        .ok()
        .map(|datetime| datetime.and_utc().timestamp())
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
}
