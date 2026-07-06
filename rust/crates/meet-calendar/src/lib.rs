use chrono::{DateTime, Duration, Utc};
use chrono_tz::Tz;
use std::str::FromStr;

#[derive(Debug, Clone)]
pub struct IcsEvent {
    pub summary: String,
    pub description: Option<String>,
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
    pub location: Option<String>,
    pub recurrence: Option<RecurrenceRule>,
    pub uid: String,
    /// IANA tzid like "Asia/Shanghai"
    pub time_zone: Option<String>,
    /// Used when `end <= start` to derive a real event length for ICS export.
    pub duration_minutes: Option<i64>,
}

#[derive(Debug, Clone)]
pub struct RecurrenceRule {
    pub frequency: RecurrenceFrequency,
    pub interval: u32,
    pub count: Option<u32>,
    pub until: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Copy)]
pub enum RecurrenceFrequency {
    Daily,
    Weekly,
    Monthly,
    Yearly,
}

impl RecurrenceFrequency {
    fn to_rrule_freq(self) -> &'static str {
        match self {
            RecurrenceFrequency::Daily => "DAILY",
            RecurrenceFrequency::Weekly => "WEEKLY",
            RecurrenceFrequency::Monthly => "MONTHLY",
            RecurrenceFrequency::Yearly => "YEARLY",
        }
    }
}

impl IcsEvent {
    /// Generate ICS file content for this event (RFC 5545 / iCalendar VERSION:2.0)
    pub fn to_ics(&self) -> String {
        let mut ics = String::new();

        // Helper: write a single ICS content line with CRLF + folding.
        // Folding rule: lines should be folded at 75 octets; continuation lines begin with a space.
        fn push_line(out: &mut String, line: &str) {
            // Simple folding by UTF-8 bytes (good enough for most cases).
            // If you need perfect "octet" folding for multi-byte chars, we can tighten this further.
            const LIMIT: usize = 75;

            let bytes = line.as_bytes();
            if bytes.len() <= LIMIT {
                out.push_str(line);
                out.push_str("\r\n");
                return;
            }

            // Fold: first line up to LIMIT, then "\r\n " + rest in chunks.
            let mut start = 0;
            let mut first = true;

            while start < bytes.len() {
                let remaining = bytes.len() - start;
                let take = if first { LIMIT } else { LIMIT - 1 }; // account for leading space
                let end = start + remaining.min(take);

                if first {
                    out.push_str(std::str::from_utf8(&bytes[start..end]).unwrap_or(""));
                    out.push_str("\r\n");
                    first = false;
                } else {
                    out.push_str(" ");
                    out.push_str(std::str::from_utf8(&bytes[start..end]).unwrap_or(""));
                    out.push_str("\r\n");
                }

                start = end;
            }
        }

        // Ensure end > start (avoid zero-length events)
        let mut end = self.end;
        if end <= self.start {
            let fallback_minutes = self.duration_minutes.filter(|minutes| *minutes > 0);
            end = self.start + Duration::minutes(fallback_minutes.unwrap_or(1));
        }

        // Calendar header
        push_line(&mut ics, "BEGIN:VCALENDAR");
        push_line(&mut ics, "VERSION:2.0");
        push_line(&mut ics, "PRODID:-//Proton Meet//EN");
        push_line(&mut ics, "CALSCALE:GREGORIAN");
        push_line(&mut ics, "METHOD:PUBLISH");

        // Optional: provide a timezone hint to clients (doesn't replace VTIMEZONE, but helps some)
        if let Some(tzid) = self.time_zone.as_deref() {
            // Only add hint if it looks parseable / IANA-ish
            if Tz::from_str(tzid).is_ok() {
                push_line(&mut ics, &format!("X-WR-TIMEZONE:{tzid}"));
            }
        }

        // Event
        push_line(&mut ics, "BEGIN:VEVENT");

        // UID
        push_line(&mut ics, &format!("UID:{}", escape_ics_text(&self.uid)));

        // DTSTAMP (UTC)
        let now = Utc::now();
        push_line(
            &mut ics,
            &format!("DTSTAMP:{}", format_datetime_ics_utc(&now)),
        );

        // DTSTART/DTEND
        if let Some(ref tzid) = self.time_zone {
            if let Ok(tz) = Tz::from_str(tzid) {
                let start_local = self.start.with_timezone(&tz);
                let end_local = end.with_timezone(&tz);

                push_line(
                    &mut ics,
                    &format!(
                        "DTSTART;TZID={}:{}",
                        tzid,
                        format_datetime_ics_local(&start_local)
                    ),
                );
                push_line(
                    &mut ics,
                    &format!(
                        "DTEND;TZID={}:{}",
                        tzid,
                        format_datetime_ics_local(&end_local)
                    ),
                );
            } else {
                // Unknown tzid: fall back to UTC and preserve original tz in custom field
                push_line(&mut ics, &format!("X-PM-TIMEZONE:{tzid}"));
                push_line(
                    &mut ics,
                    &format!("DTSTART:{}", format_datetime_ics_utc(&self.start)),
                );
                push_line(
                    &mut ics,
                    &format!("DTEND:{}", format_datetime_ics_utc(&end)),
                );
            }
        } else {
            push_line(
                &mut ics,
                &format!("DTSTART:{}", format_datetime_ics_utc(&self.start)),
            );
            push_line(
                &mut ics,
                &format!("DTEND:{}", format_datetime_ics_utc(&end)),
            );
        }

        // SUMMARY
        push_line(
            &mut ics,
            &format!("SUMMARY:{}", escape_ics_text(&self.summary)),
        );

        // DESCRIPTION
        if let Some(ref desc) = self.description {
            push_line(&mut ics, &format!("DESCRIPTION:{}", escape_ics_text(desc)));
        }

        // LOCATION
        if let Some(ref loc) = self.location {
            push_line(&mut ics, &format!("LOCATION:{}", escape_ics_text(loc)));
        }

        // RRULE
        if let Some(ref rrule) = self.recurrence {
            let mut rule = format!("RRULE:FREQ={}", rrule.frequency.to_rrule_freq());

            if rrule.interval > 1 {
                rule.push_str(&format!(";INTERVAL={}", rrule.interval));
            }

            // Prefer COUNT over UNTIL if both are present (optional policy; adjust as you like)
            if let Some(count) = rrule.count {
                rule.push_str(&format!(";COUNT={count}"));
            } else if let Some(until) = rrule.until {
                // UNTIL must be in UTC with Z in RFC 5545 when DTSTART is date-time
                rule.push_str(&format!(";UNTIL={}", format_datetime_ics_utc(&until)));
            }

            push_line(&mut ics, &rule);
        }

        // STATUS / SEQUENCE
        push_line(&mut ics, "STATUS:CONFIRMED");
        push_line(&mut ics, "SEQUENCE:0");

        // End event/calendar
        push_line(&mut ics, "END:VEVENT");
        push_line(&mut ics, "END:VCALENDAR");

        ics
    }
}

/// Format UTC DateTime as ICS format (YYYYMMDDTHHMMSSZ)
fn format_datetime_ics_utc(dt: &DateTime<Utc>) -> String {
    dt.format("%Y%m%dT%H%M%SZ").to_string()
}

/// Format local DateTime as ICS local format (YYYYMMDDTHHMMSS)
fn format_datetime_ics_local(dt: &chrono::DateTime<Tz>) -> String {
    dt.format("%Y%m%dT%H%M%S").to_string()
}

/// Escape special characters in ICS text fields (RFC 5545 TEXT)
fn escape_ics_text(text: &str) -> String {
    text.replace('\\', "\\\\")
        .replace(';', "\\;")
        .replace(',', "\\,")
        .replace('\r', "")
        .replace('\n', "\\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn utc_datetime(
        year: i32,
        month: u32,
        day: u32,
        hour: u32,
        minute: u32,
        second: u32,
    ) -> Result<DateTime<Utc>, Box<dyn std::error::Error>> {
        Utc.with_ymd_and_hms(year, month, day, hour, minute, second)
            .single()
            .ok_or_else(|| "Invalid UTC datetime".into())
    }

    fn dtend_line_from_ics(ics: &str) -> Option<String> {
        ics.lines()
            .map(str::trim)
            .find(|line| line.starts_with("DTEND"))
            .map(str::to_string)
    }

    fn build_ics_event(
        start: DateTime<Utc>,
        end: DateTime<Utc>,
        time_zone: Option<&str>,
        duration_minutes: Option<i64>,
    ) -> String {
        sample_event(start, end, time_zone, duration_minutes, |_| {}).to_ics()
    }

    fn sample_event(
        start: DateTime<Utc>,
        end: DateTime<Utc>,
        time_zone: Option<&str>,
        duration_minutes: Option<i64>,
        mutate: impl FnOnce(&mut IcsEvent),
    ) -> IcsEvent {
        let mut event = IcsEvent {
            summary: "Test".to_string(),
            description: Some("https://meet.proton.me/join/id-aaaabbbbb#pwd-dddddd".to_string()),
            start,
            end,
            location: None,
            recurrence: None,
            uid: format!("proton-meet-{}-{}", start.timestamp(), end.timestamp()),
            time_zone: time_zone.map(str::to_string),
            duration_minutes,
        };
        mutate(&mut event);
        event
    }

    fn line_from_ics<'a>(ics: &'a str, prefix: &str) -> Option<&'a str> {
        ics.lines()
            .map(str::trim)
            .find(|line| line.starts_with(prefix))
    }

    #[test]
    fn test_ics_export_basic() -> Result<(), Box<dyn std::error::Error>> {
        let event = IcsEvent {
            summary: "Test Meeting".to_string(),
            description: Some("Test Description".to_string()),
            start: utc_datetime(2026, 1, 9, 13, 20, 0)?,
            end: utc_datetime(2026, 1, 9, 14, 20, 0)?,
            location: None,
            recurrence: None,
            uid: "test-uid-123".to_string(),
            time_zone: None,
            duration_minutes: None,
        };

        let ics = event.to_ics();
        assert!(ics.contains("BEGIN:VCALENDAR"));
        assert!(ics.contains("BEGIN:VEVENT"));
        assert!(ics.contains("SUMMARY:Test Meeting"));
        assert!(ics.contains("END:VEVENT"));
        assert!(ics.contains("END:VCALENDAR"));
        Ok(())
    }

    #[test]
    fn test_ics_export_with_recurrence() -> Result<(), Box<dyn std::error::Error>> {
        let event = IcsEvent {
            summary: "Weekly Meeting".to_string(),
            description: None,
            start: utc_datetime(2026, 1, 9, 13, 20, 0)?,
            end: utc_datetime(2026, 1, 9, 14, 20, 0)?,
            location: None,
            recurrence: Some(RecurrenceRule {
                frequency: RecurrenceFrequency::Weekly,
                interval: 1,
                count: Some(10),
                until: None,
            }),
            uid: "weekly-meeting-123".to_string(),
            time_zone: None,
            duration_minutes: None,
        };

        let ics = event.to_ics();
        assert!(ics.contains("RRULE:FREQ=WEEKLY;COUNT=10"));
        Ok(())
    }

    /// A meeting with a real start/end should preserve its duration in the exported ICS.
    #[test]
    fn ics_event_reflects_meeting_duration_in_timezone() -> Result<(), Box<dyn std::error::Error>> {
        // 30-minute meeting at 13:53 Europe/Berlin on 2026-07-01 (CEST, UTC+2).
        let start = utc_datetime(2026, 7, 1, 11, 53, 0)?;
        let end = start + Duration::minutes(30);

        let ics = build_ics_event(start, end, Some("Europe/Berlin"), None);

        assert!(ics.contains("DTSTART;TZID=Europe/Berlin:20260701T135300"));
        assert_eq!(
            dtend_line_from_ics(&ics).as_deref(),
            Some("DTEND;TZID=Europe/Berlin:20260701T142300"),
            "DTEND should be 30 minutes after DTSTART.\nICS:\n{ics}"
        );
        Ok(())
    }

    /// Reproduces the reported bug: when end_timestamp equals start_timestamp (as in
    /// `UID:proton-meet-{ts}-{ts}`), ICS export must not fall back to a 1-minute event.
    #[test]
    fn ics_export_uses_real_duration_when_start_and_end_timestamps_match(
    ) -> Result<(), Box<dyn std::error::Error>> {
        let start = utc_datetime(2026, 7, 1, 11, 53, 0)?;
        let intended_duration_minutes = 30;

        // Mirrors production: Flutter may send identical start/end timestamps.
        let ics = build_ics_event(
            start,
            start,
            Some("Europe/Berlin"),
            Some(intended_duration_minutes),
        );

        let expected_dtend = format!(
            "DTEND;TZID=Europe/Berlin:{}",
            format_datetime_ics_local(
                &(start + Duration::minutes(intended_duration_minutes))
                    .with_timezone(&Tz::Europe__Berlin)
            )
        );

        assert_eq!(
            dtend_line_from_ics(&ics).as_deref(),
            Some(expected_dtend.as_str()),
            "ICS should reflect the real meeting duration instead of a 1-minute fallback.\nICS:\n{ics}"
        );
        Ok(())
    }

    #[test]
    fn ics_export_escapes_special_characters_in_text_fields(
    ) -> Result<(), Box<dyn std::error::Error>> {
        let start = utc_datetime(2026, 1, 9, 13, 20, 0)?;
        let end = start + Duration::hours(1);
        let event = sample_event(start, end, None, None, |event| {
            event.summary = "Meet\\;ing, summary\nnext".to_string();
            event.description = Some("Room\\;A, floor\r1\nlink".to_string());
            event.location = Some("Berlin;DE, HQ".to_string());
            event.uid = "uid\\;with,special".to_string();
        });

        let ics = event.to_ics();
        assert_eq!(
            line_from_ics(&ics, "SUMMARY:"),
            Some(format!("SUMMARY:{}", escape_ics_text("Meet\\;ing, summary\nnext")).as_str())
        );
        assert_eq!(
            line_from_ics(&ics, "DESCRIPTION:"),
            Some(
                format!(
                    "DESCRIPTION:{}",
                    escape_ics_text("Room\\;A, floor\r1\nlink")
                )
                .as_str()
            )
        );
        assert_eq!(
            line_from_ics(&ics, "LOCATION:"),
            Some(format!("LOCATION:{}", escape_ics_text("Berlin;DE, HQ")).as_str())
        );
        assert_eq!(
            line_from_ics(&ics, "UID:"),
            Some(format!("UID:{}", escape_ics_text("uid\\;with,special")).as_str())
        );
        Ok(())
    }

    #[test]
    fn ics_export_includes_location() -> Result<(), Box<dyn std::error::Error>> {
        let start = utc_datetime(2026, 1, 9, 13, 20, 0)?;
        let end = start + Duration::hours(1);
        let ics = sample_event(start, end, None, None, |event| {
            event.location = Some("Proton Office".to_string());
        })
        .to_ics();

        assert_eq!(
            line_from_ics(&ics, "LOCATION:"),
            Some("LOCATION:Proton Office")
        );
        Ok(())
    }

    #[test]
    fn ics_export_unknown_timezone_falls_back_to_utc() -> Result<(), Box<dyn std::error::Error>> {
        let start = utc_datetime(2026, 1, 9, 13, 20, 0)?;
        let end = start + Duration::hours(1);
        let ics = sample_event(start, end, Some("Not/A/Real/Zone"), None, |_| {}).to_ics();

        assert_eq!(
            line_from_ics(&ics, "X-PM-TIMEZONE:"),
            Some("X-PM-TIMEZONE:Not/A/Real/Zone")
        );
        assert!(!ics.contains("X-WR-TIMEZONE:"));
        assert_eq!(
            line_from_ics(&ics, "DTSTART:"),
            Some("DTSTART:20260109T132000Z")
        );
        assert_eq!(
            line_from_ics(&ics, "DTEND:"),
            Some("DTEND:20260109T142000Z")
        );
        Ok(())
    }

    #[test]
    fn ics_export_defaults_to_one_minute_without_duration() -> Result<(), Box<dyn std::error::Error>>
    {
        let start = utc_datetime(2026, 7, 1, 11, 53, 0)?;
        let ics = build_ics_event(start, start, Some("Europe/Berlin"), None);

        assert_eq!(
            dtend_line_from_ics(&ics).as_deref(),
            Some("DTEND;TZID=Europe/Berlin:20260701T135400")
        );
        Ok(())
    }

    #[test]
    fn ics_export_ignores_non_positive_duration_minutes() -> Result<(), Box<dyn std::error::Error>>
    {
        let start = utc_datetime(2026, 7, 1, 11, 53, 0)?;
        let ics = build_ics_event(start, start, Some("Europe/Berlin"), Some(0));

        assert_eq!(
            dtend_line_from_ics(&ics).as_deref(),
            Some("DTEND;TZID=Europe/Berlin:20260701T135400")
        );
        Ok(())
    }

    #[test]
    fn ics_export_recurrence_supports_all_frequencies() -> Result<(), Box<dyn std::error::Error>> {
        let start = utc_datetime(2026, 1, 9, 13, 20, 0)?;
        let end = start + Duration::hours(1);

        let cases = [
            (RecurrenceFrequency::Daily, "RRULE:FREQ=DAILY;COUNT=3"),
            (RecurrenceFrequency::Weekly, "RRULE:FREQ=WEEKLY;COUNT=3"),
            (RecurrenceFrequency::Monthly, "RRULE:FREQ=MONTHLY;COUNT=3"),
            (RecurrenceFrequency::Yearly, "RRULE:FREQ=YEARLY;COUNT=3"),
        ];

        for (frequency, expected_rule) in cases {
            let ics = sample_event(start, end, None, None, |event| {
                event.recurrence = Some(RecurrenceRule {
                    frequency,
                    interval: 1,
                    count: Some(3),
                    until: None,
                });
            })
            .to_ics();
            assert!(
                ics.contains(expected_rule),
                "missing rule for {frequency:?}"
            );
        }
        Ok(())
    }

    #[test]
    fn ics_export_recurrence_with_interval_and_until() -> Result<(), Box<dyn std::error::Error>> {
        let start = utc_datetime(2026, 1, 9, 13, 20, 0)?;
        let end = start + Duration::hours(1);
        let until = utc_datetime(2026, 12, 31, 23, 59, 0)?;
        let ics = sample_event(start, end, None, None, |event| {
            event.recurrence = Some(RecurrenceRule {
                frequency: RecurrenceFrequency::Daily,
                interval: 2,
                count: None,
                until: Some(until),
            });
        })
        .to_ics();

        let rrule = line_from_ics(&ics, "RRULE:").unwrap_or("");
        assert!(rrule.contains("FREQ=DAILY"));
        assert!(rrule.contains("INTERVAL=2"));
        assert!(rrule.contains("UNTIL=20261231T235900Z"), "got: {rrule}");
        Ok(())
    }

    #[test]
    fn ics_export_recurrence_prefers_count_over_until() -> Result<(), Box<dyn std::error::Error>> {
        let start = utc_datetime(2026, 1, 9, 13, 20, 0)?;
        let end = start + Duration::hours(1);
        let until = utc_datetime(2026, 12, 31, 23, 59, 0)?;
        let ics = sample_event(start, end, None, None, |event| {
            event.recurrence = Some(RecurrenceRule {
                frequency: RecurrenceFrequency::Monthly,
                interval: 1,
                count: Some(5),
                until: Some(until),
            });
        })
        .to_ics();

        assert!(ics.contains("RRULE:FREQ=MONTHLY;COUNT=5"));
        assert!(!ics.contains("UNTIL="));
        Ok(())
    }

    #[test]
    fn ics_export_folds_multiline_description_chunks() {
        let start = utc_datetime(2026, 1, 9, 13, 20, 0).unwrap();
        let end = start + Duration::hours(1);
        let ics = sample_event(start, end, None, None, |event| {
            event.description = Some("y".repeat(200));
        })
        .to_ics();

        assert!(ics.matches("\r\n ").count() >= 2);
    }

    #[test]
    fn ics_export_folds_long_description_lines() -> Result<(), Box<dyn std::error::Error>> {
        let start = utc_datetime(2026, 1, 9, 13, 20, 0)?;
        let end = start + Duration::hours(1);
        let long_description = format!("DESCRIPTION:{}", "x".repeat(120));
        let ics = sample_event(start, end, None, None, |event| {
            event.description = Some("x".repeat(120));
        })
        .to_ics();

        assert!(!ics.contains(&long_description));
        assert!(ics.contains("DESCRIPTION:"));
        assert!(ics.contains("\r\n "));
        Ok(())
    }

    #[test]
    fn utc_datetime_rejects_invalid_values() {
        assert!(utc_datetime(2026, 2, 30, 13, 20, 0).is_err());
    }
}
