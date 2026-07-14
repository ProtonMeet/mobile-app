//! Enriches create-meeting failures with stable debug context for clients (FRB)
//! and structured logs.

use crate::domain::user::models::meeting::MeetingType;
use crate::errors::core::MeetCoreError;
use crate::errors::service::ServiceError;

/// Non-sensitive fields only (no mailbox password, no private key material).
#[derive(Debug, Clone)]
pub struct CreateMeetingErrorContext {
    pub meeting_type: MeetingType,
    pub has_session: bool,
    /// True when the mailbox password string is empty (common unlock/crypto failure mode).
    pub mailbox_password_empty: bool,
    /// Whether the signing user key is marked primary (`ProtonUserKey::primary != 0`).
    pub signing_key_primary: bool,
    /// Whether the signing user key is marked active (`ProtonUserKey::active != 0`).
    pub signing_key_active: bool,
}

fn debug_suffix(ctx: &CreateMeetingErrorContext) -> String {
    format!(
        "create_meeting_debug meeting_type={:?} has_session={} mailbox_password_empty={} signing_key_primary={} signing_key_active={}",
        ctx.meeting_type,
        ctx.has_session,
        ctx.mailbox_password_empty,
        ctx.signing_key_primary,
        ctx.signing_key_active,
    )
}

/// Maps a [`ServiceError`] from [`crate::domain::room::RoomService::create_meeting`]
/// into [`MeetCoreError`] and appends [`CreateMeetingErrorContext`] for Flutter/Sentry.
pub fn map_create_meeting_service_error(
    err: ServiceError,
    ctx: &CreateMeetingErrorContext,
) -> MeetCoreError {
    let mapped = MeetCoreError::from(err);
    let out = merge_create_meeting_context(mapped, ctx);
    log_create_meeting_failure(&out, ctx);
    out
}

fn merge_create_meeting_context(
    err: MeetCoreError,
    ctx: &CreateMeetingErrorContext,
) -> MeetCoreError {
    let suffix = debug_suffix(ctx);
    match err {
        MeetCoreError::ServiceError { message, details } => {
            let merged = match details {
                Some(d) => format!("{suffix} | underlying_source={d}"),
                None => suffix,
            };
            MeetCoreError::ServiceError {
                message,
                details: Some(merged),
            }
        }
        MeetCoreError::HttpClientError {
            status,
            message,
            details,
        } => {
            let merged = match details {
                Some(d) => format!("{suffix} | prior_details={d}"),
                None => suffix,
            };
            MeetCoreError::HttpClientError {
                status,
                message,
                details: Some(merged),
            }
        }
        other => other,
    }
}

fn log_create_meeting_failure(err: &MeetCoreError, ctx: &CreateMeetingErrorContext) {
    match err {
        MeetCoreError::ServiceError { message, details } => {
            tracing::error!(
                target: "meet_core::create_meeting",
                meeting_type = ?ctx.meeting_type,
                has_session = ctx.has_session,
                mailbox_password_empty = ctx.mailbox_password_empty,
                signing_key_primary = ctx.signing_key_primary,
                signing_key_active = ctx.signing_key_active,
                error = %message,
                ?details,
                "create_meeting failed (service)"
            );
        }
        MeetCoreError::HttpClientError {
            status,
            message,
            details,
        } => {
            tracing::error!(
                target: "meet_core::create_meeting",
                meeting_type = ?ctx.meeting_type,
                has_session = ctx.has_session,
                mailbox_password_empty = ctx.mailbox_password_empty,
                signing_key_primary = ctx.signing_key_primary,
                signing_key_active = ctx.signing_key_active,
                http_status = status,
                error = %message,
                ?details,
                "create_meeting failed (http)"
            );
        }
        _ => {
            tracing::error!(
                target: "meet_core::create_meeting",
                meeting_type = ?ctx.meeting_type,
                has_session = ctx.has_session,
                mailbox_password_empty = ctx.mailbox_password_empty,
                signing_key_primary = ctx.signing_key_primary,
                signing_key_active = ctx.signing_key_active,
                error = %err,
                "create_meeting failed"
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::errors::http_client::{HttpClientError, ResponseError};
    use muon::http::Status;

    fn sample_ctx() -> CreateMeetingErrorContext {
        CreateMeetingErrorContext {
            meeting_type: MeetingType::Permanent,
            has_session: true,
            mailbox_password_empty: false,
            signing_key_primary: true,
            signing_key_active: true,
        }
    }

    #[test]
    fn service_error_includes_create_meeting_debug_suffix() {
        let ctx = sample_ctx();
        let out = map_create_meeting_service_error(ServiceError::UserPrivateKeysNotFound, &ctx);
        let MeetCoreError::ServiceError { details, .. } = out else {
            panic!("expected ServiceError, got {out:?}");
        };
        let d = details.expect("details");
        assert!(d.contains("create_meeting_debug"));
        assert!(d.contains("signing_key_primary=true"));
        assert!(d.contains("signing_key_active=true"));
        assert!(d.contains("mailbox_password_empty=false"));
        assert!(d.contains("underlying_source"));
    }

    #[test]
    fn http_client_error_merges_debug_into_details() {
        let ctx = sample_ctx();
        let svc_err = ServiceError::HttpClientError(HttpClientError::ErrorCode(
            Status::from_u16(422).unwrap(),
            ResponseError {
                code: 422,
                error: "validation".to_string(),
                details: serde_json::Value::Null,
            },
        ));
        let out = map_create_meeting_service_error(svc_err, &ctx);
        let MeetCoreError::HttpClientError {
            status, details, ..
        } = out
        else {
            panic!("expected HttpClientError, got {out:?}");
        };
        assert_eq!(status, 422);
        let d = details.expect("details");
        assert!(d.contains("create_meeting_debug"));
        assert!(d.contains("prior_details"));
    }
}
