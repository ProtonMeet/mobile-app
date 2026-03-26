use proton_meet_macro::async_trait_with_mock;

use crate::{
    domain::user::models::{
        meeting::{CreateMeetingParams, Meeting, UpdateMeetingScheduleParams},
        MeetingInfo,
    },
    errors::http_client::HttpClientError,
};

#[async_trait_with_mock]
pub trait MeetingApi: Send + Sync {
    async fn get_upcoming_meetings(&self) -> Result<Vec<Meeting>, HttpClientError>;
    async fn create_meeting(
        &self,
        meeting: CreateMeetingParams,
    ) -> Result<Meeting, HttpClientError>;
    async fn edit_meeting_name(
        &self,
        meeting_id: &str,
        meeting_name: &str,
    ) -> Result<Meeting, HttpClientError>;
    async fn update_meeting_schedule(
        &self,
        meeting_id: &str,
        params: UpdateMeetingScheduleParams,
    ) -> Result<Meeting, HttpClientError>;
    async fn delete_meeting(&self, meeting_id: &str) -> Result<(), HttpClientError>;

    async fn rotate_personal_meeting(
        &self,
        meeting: CreateMeetingParams,
    ) -> Result<Meeting, HttpClientError>;

    async fn end_meeting(
        &self,
        meeting_name: &str,
        access_token: &str,
    ) -> Result<(), HttpClientError>;

    async fn get_meeting_info(&self, meeting_name: &str) -> Result<MeetingInfo, HttpClientError>;

    async fn fetch_meeting(&self, meeting_id: &str) -> Result<Meeting, HttpClientError>;

    /// Lock a meeting to prevent new participants from joining (meeting host only)
    async fn lock_meeting(&self, meet_link_name: &str) -> Result<(), HttpClientError>;

    /// Unlock a meeting to allow new participants to join (meeting host only)
    async fn unlock_meeting(&self, meet_link_name: &str) -> Result<(), HttpClientError>;
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::user::models::meeting::{CustomPasswordSetting, MeetingType};
    use crate::errors::http_client::HttpClientError;
    use proton_meet_macro::unified_test;

    fn sample_create_params(name: &str) -> CreateMeetingParams {
        CreateMeetingParams {
            name: name.to_string(),
            password: Some("encrypted-password".to_string()),
            salt: "salt".to_string(),
            session_key: "session-key".to_string(),
            srp_modulus_id: "modulus-id".to_string(),
            srp_salt: "srp-salt".to_string(),
            srp_verifier: "srp-verifier".to_string(),
            address_id: Some("addr".to_string()),
            start_time: None,
            end_time: None,
            r_rule: None,
            time_zone: None,
            custom_password: CustomPasswordSetting::NoPassword as u8,
            meeting_type: MeetingType::Instant as u8,
        }
    }

    fn sample_meeting(id: &str, name: &str) -> Meeting {
        Meeting {
            id: id.to_string(),
            meeting_link_name: "link".to_string(),
            meeting_name: name.to_string(),
            salt: "salt".to_string(),
            session_key: "session-key".to_string(),
            srp_modulus_id: "modulus-id".to_string(),
            srp_salt: "srp-salt".to_string(),
            srp_verifier: "srp-verifier".to_string(),
            custom_password: CustomPasswordSetting::NoPassword,
            meeting_type: MeetingType::Instant,
            ..Default::default()
        }
    }

    fn sample_meeting_info() -> MeetingInfo {
        MeetingInfo {
            meeting_link_name: "link".to_string(),
            meeting_name: "encrypted-name".to_string(),
            salt: "salt".to_string(),
            session_key: "session-key".to_string(),
            locked: 0,
            max_duration: 3600,
            max_participants: 25,
            expiration_time: None,
        }
    }

    #[unified_test]
    async fn test_get_upcoming_meetings_success() {
        let mut mock = MockMeetingApi::new();
        let meetings = vec![sample_meeting("id-1", "name-1")];

        mock.expect_get_upcoming_meetings().returning(move || {
            Box::pin({
                let value = meetings.clone();
                async move { Ok(value.clone()) }
            })
        });

        let result = mock.get_upcoming_meetings().await.unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].id, "id-1");
    }

    #[unified_test]
    async fn test_get_upcoming_meetings_failure() {
        let mut mock = MockMeetingApi::new();

        mock.expect_get_upcoming_meetings().returning(|| {
            Box::pin(async {
                Err(HttpClientError::MlsHttpError {
                    message: "fetch failed".into(),
                })
            })
        });

        let result = mock.get_upcoming_meetings().await;
        assert!(matches!(
            result,
            Err(HttpClientError::MlsHttpError { message: _ })
        ));
    }

    #[unified_test]
    async fn test_create_meeting_success_1() {
        let mut mock = MockMeetingApi::new();
        let params = sample_create_params("enc-name");
        let created = sample_meeting("id-1", "enc-name");

        mock.expect_create_meeting()
            .withf(|p| p.name == "enc-name")
            .returning(move |_| {
                let created = created.clone();
                Box::pin(async move { Ok(created) })
            });

        let result = mock.create_meeting(params).await.unwrap();
        assert_eq!(result.id, "id-1");
        assert_eq!(result.meeting_name, "enc-name");
    }

    #[unified_test]
    async fn test_edit_meeting_name_success() {
        let mut mock = MockMeetingApi::new();
        let updated = sample_meeting("id-2", "new-name");

        mock.expect_edit_meeting_name()
            .withf(|id, name| id == "id-2" && name == "new-name")
            .returning(move |_, _| {
                let updated = updated.clone();
                Box::pin(async move { Ok(updated) })
            });

        let result = mock.edit_meeting_name("id-2", "new-name").await.unwrap();
        assert_eq!(result.meeting_name, "new-name");
    }

    #[unified_test]
    async fn test_delete_meeting_success() {
        let mut mock = MockMeetingApi::new();

        mock.expect_delete_meeting()
            .withf(|name| name == "link-name")
            .returning(|_| Box::pin(async { Ok(()) }));

        let result = mock.delete_meeting("link-name").await;
        assert!(result.is_ok());
    }

    #[unified_test]
    async fn test_rotate_personal_meeting_success() {
        let mut mock = MockMeetingApi::new();
        let params = sample_create_params("enc-rotate");
        let rotated = sample_meeting("id-3", "enc-rotate");

        mock.expect_rotate_personal_meeting()
            .withf(|p| p.name == "enc-rotate")
            .returning(move |_| {
                let rotated = rotated.clone();
                Box::pin(async move { Ok(rotated) })
            });

        let result = mock.rotate_personal_meeting(params).await.unwrap();
        assert_eq!(result.id, "id-3");
    }

    #[unified_test]
    async fn test_end_meeting_success() {
        let mut mock = MockMeetingApi::new();

        mock.expect_end_meeting()
            .withf(|name, token| name == "link-name" && token == "token")
            .returning(|_, _| Box::pin(async { Ok(()) }));

        let result = mock.end_meeting("link-name", "token").await;
        assert!(result.is_ok());
    }

    #[unified_test]
    async fn test_get_meeting_info_success() {
        let mut mock = MockMeetingApi::new();
        let info = sample_meeting_info();

        mock.expect_get_meeting_info()
            .withf(|name| name == "link-name")
            .returning(move |_| {
                let info = info.clone();
                Box::pin(async move { Ok(info) })
            });

        let result = mock.get_meeting_info("link-name").await.unwrap();
        assert_eq!(result.meeting_link_name, "link");
    }

    #[unified_test]
    async fn test_fetch_meeting_success() {
        let mut mock = MockMeetingApi::new();
        let meeting = sample_meeting("id-4", "enc-name");

        mock.expect_fetch_meeting()
            .withf(|id| id == "id-4")
            .returning(move |_| {
                let meeting = meeting.clone();
                Box::pin(async move { Ok(meeting) })
            });

        let result = mock.fetch_meeting("id-4").await.unwrap();
        assert_eq!(result.id, "id-4");
    }
}
