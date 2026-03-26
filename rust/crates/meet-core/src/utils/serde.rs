use chrono::DateTime;
use serde::de::{self, Visitor};
use serde::Deserializer;
use std::fmt;

/// Custom deserializer that handles both integer (Unix timestamp) and string (RFC3339) formats
///
/// This function can be used with `#[serde(deserialize_with = "crate::utils::serde::deserialize_timestamp")]`
/// to deserialize timestamp fields that may come as either:
/// - Integer Unix timestamps (e.g., `1746518400`)
/// - RFC3339 strings (e.g., `"2025-01-06T10:00:00Z"`)
/// - `null` values
///
/// The function converts integer timestamps to RFC3339 strings, passes through string timestamps,
/// and returns `None` for null values.
pub fn deserialize_timestamp<'de, D>(deserializer: D) -> Result<Option<String>, D::Error>
where
    D: Deserializer<'de>,
{
    struct TimestampVisitor;

    impl<'de> Visitor<'de> for TimestampVisitor {
        type Value = Option<String>;

        fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
            formatter.write_str("an integer (Unix timestamp) or a string (RFC3339) or null")
        }

        fn visit_none<E>(self) -> Result<Self::Value, E>
        where
            E: de::Error,
        {
            Ok(None)
        }

        fn visit_some<D>(self, deserializer: D) -> Result<Self::Value, D::Error>
        where
            D: Deserializer<'de>,
        {
            deserializer.deserialize_any(TimestampVisitor)
        }

        fn visit_unit<E>(self) -> Result<Self::Value, E>
        where
            E: de::Error,
        {
            Ok(None)
        }

        fn visit_i64<E>(self, value: i64) -> Result<Self::Value, E>
        where
            E: de::Error,
        {
            // Convert Unix timestamp to RFC3339 string
            let dt = DateTime::from_timestamp(value, 0)
                .ok_or_else(|| E::custom(format!("Invalid timestamp: {value}")))?;
            Ok(Some(dt.to_rfc3339()))
        }

        fn visit_u64<E>(self, value: u64) -> Result<Self::Value, E>
        where
            E: de::Error,
        {
            // Convert Unix timestamp to RFC3339 string
            let dt = DateTime::from_timestamp(value as i64, 0)
                .ok_or_else(|| E::custom(format!("Invalid timestamp: {value}")))?;
            Ok(Some(dt.to_rfc3339()))
        }

        fn visit_str<E>(self, value: &str) -> Result<Self::Value, E>
        where
            E: de::Error,
        {
            // Already a string, return as-is
            Ok(Some(value.to_string()))
        }

        fn visit_string<E>(self, value: String) -> Result<Self::Value, E>
        where
            E: de::Error,
        {
            Ok(Some(value))
        }
    }

    deserializer.deserialize_option(TimestampVisitor)
}

