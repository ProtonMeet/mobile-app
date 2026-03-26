use chrono::{DateTime, Duration, Utc};
use chrono_tz::Tz;
use std::fmt::{self, Write};
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
    pub fn to_ics(&self) -> Result<String, fmt::Error> {
        let mut ics = String::new();

        // Helper: write a single ICS content line with CRLF + folding.
        // Folding rule: lines should be folded at 75 octets; continuation lines begin with a space.
        fn push_line(out: &mut String, line: &str) -> Result<(), fmt::Error> {
            // Simple folding by UTF-8 bytes (good enough for most cases).
            // If you need perfect "octet" folding for multi-byte chars, we can tighten this further.
            const LIMIT: usize = 75;

            let bytes = line.as_bytes();
            if bytes.len() <= LIMIT {
                out.write_str(line)?;
                out.write_str("\r\n")?;
                return Ok(());
            }

            // Fold: first line up to LIMIT, then "\r\n " + rest in chunks.
            let mut start = 0;
            let mut first = true;

            while start < bytes.len() {
                let remaining = bytes.len() - start;
                let take = if first { LIMIT } else { LIMIT - 1 }; // account for leading space
                let end = start + remaining.min(take);

                if first {
                    out.write_str(std::str::from_utf8(&bytes[start..end]).unwrap_or(""))?;
                    out.write_str("\r\n")?;
                    first = false;
                } else {
                    out.write_str(" ")?;
                    out.write_str(std::str::from_utf8(&bytes[start..end]).unwrap_or(""))?;
                    out.write_str("\r\n")?;
                }

                start = end;
            }

            Ok(())
        }

        // Ensure end > start (avoid zero-length events)
        let mut end = self.end;
        if end <= self.start {
            end = self.start + Duration::minutes(1);
        }

        // Calendar header
        push_line(&mut ics, "BEGIN:VCALENDAR")?;
        push_line(&mut ics, "VERSION:2.0")?;
        push_line(&mut ics, "PRODID:-//Proton Meet//EN")?;
        push_line(&mut ics, "CALSCALE:GREGORIAN")?;
        push_line(&mut ics, "METHOD:PUBLISH")?;

        // Optional: provide a timezone hint to clients (doesn't replace VTIMEZONE, but helps some)
        if let Some(tzid) = self.time_zone.as_deref() {
            // Only add hint if it looks parseable / IANA-ish
            if Tz::from_str(tzid).is_ok() {
                push_line(&mut ics, &format!("X-WR-TIMEZONE:{tzid}"))?;
            }
        }

        // Event
        push_line(&mut ics, "BEGIN:VEVENT")?;

        // UID
        push_line(&mut ics, &format!("UID:{}", escape_ics_text(&self.uid)))?;

        // DTSTAMP (UTC)
        let now = Utc::now();
        push_line(
            &mut ics,
            &format!("DTSTAMP:{}", format_datetime_ics_utc(&now)),
        )?;

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
                )?;
                push_line(
                    &mut ics,
                    &format!(
                        "DTEND;TZID={}:{}",
                        tzid,
                        format_datetime_ics_local(&end_local)
                    ),
                )?;
            } else {
                // Unknown tzid: fall back to UTC and preserve original tz in custom field
                push_line(&mut ics, &format!("X-PM-TIMEZONE:{tzid}"))?;
                push_line(
                    &mut ics,
                    &format!("DTSTART:{}", format_datetime_ics_utc(&self.start)),
                )?;
                push_line(
                    &mut ics,
                    &format!("DTEND:{}", format_datetime_ics_utc(&end)),
                )?;
            }
        } else {
            push_line(
                &mut ics,
                &format!("DTSTART:{}", format_datetime_ics_utc(&self.start)),
            )?;
            push_line(
                &mut ics,
                &format!("DTEND:{}", format_datetime_ics_utc(&end)),
            )?;
        }

        // SUMMARY
        push_line(
            &mut ics,
            &format!("SUMMARY:{}", escape_ics_text(&self.summary)),
        )?;

        // DESCRIPTION
        if let Some(ref desc) = self.description {
            push_line(&mut ics, &format!("DESCRIPTION:{}", escape_ics_text(desc)))?;
        }

        // LOCATION
        if let Some(ref loc) = self.location {
            push_line(&mut ics, &format!("LOCATION:{}", escape_ics_text(loc)))?;
        }

        // RRULE
        if let Some(ref rrule) = self.recurrence {
            let mut rule = format!("RRULE:FREQ={}", rrule.frequency.to_rrule_freq());

            if rrule.interval > 1 {
                write!(&mut rule, ";INTERVAL={}", rrule.interval)?;
            }

            // Prefer COUNT over UNTIL if both are present (optional policy; adjust as you like)
            if let Some(count) = rrule.count {
                write!(&mut rule, ";COUNT={count}")?;
            } else if let Some(until) = rrule.until {
                // UNTIL must be in UTC with Z in RFC 5545 when DTSTART is date-time
                write!(&mut rule, ";UNTIL={}", format_datetime_ics_utc(&until))?;
            }

            push_line(&mut ics, &rule)?;
        }

        // STATUS / SEQUENCE
        push_line(&mut ics, "STATUS:CONFIRMED")?;
        push_line(&mut ics, "SEQUENCE:0")?;

        // End event/calendar
        push_line(&mut ics, "END:VEVENT")?;
        push_line(&mut ics, "END:VCALENDAR")?;

        Ok(ics)
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
        };

        let ics = event.to_ics()?;
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
        };

        let ics = event.to_ics()?;
        assert!(ics.contains("RRULE:FREQ=WEEKLY;COUNT=10"));
        Ok(())
    }
}
