use proton_meet_macro::async_trait;

use crate::domain::user::models::meeting::Meeting;
use crate::domain::user::models::{CreateMeetingParams, MeetingInfo, UpdateMeetingScheduleParams};
use crate::domain::user::ports::meeting_api::MeetingApi;
use crate::errors::http_client::HttpClientError;
use crate::infra::dto::common::ProtonEmptyResponse;
use crate::infra::dto::end_meeting::EndMeetingRequest;
use crate::infra::dto::meeting::{
    CreateMeetingRequest, CreateMeetingResponse, EditMeetingNameRequest, FetchMeetingResponse,
    MeetingInfoResponse, UpcomingMeetingsResponse, UpdateMeetingResponse,
    UpdateMeetingScheduleRequest,
};
use crate::infra::http_client::ProtonHttpClient;
use crate::infra::http_client_util::HttpClientUtil;
use crate::infra::proton_response_ext::ProtonResponseExt;

#[async_trait]
impl MeetingApi for ProtonHttpClient {
    async fn get_upcoming_meetings(&self) -> Result<Vec<Meeting>, HttpClientError> {
        let req = self.get("/meet/v1/meetings/upcoming");
        let res = self.get_session().send(req).await?;
        let upcoming_meetings_res = res.parse_response::<UpcomingMeetingsResponse>()?;
        Ok(upcoming_meetings_res
            .meetings
            .into_iter()
            .map(|m| m.try_into())
            .collect::<Result<Vec<Meeting>, _>>()?)
    }

    async fn create_meeting(
        &self,
        meeting: CreateMeetingParams,
    ) -> Result<Meeting, HttpClientError> {
        let body: CreateMeetingRequest = meeting.into();
        let req = self.post("/meet/v1/meetings").body_json(body)?;
        let res = self.get_session().send(req).await?;
        let meeting_res = res.parse_response::<CreateMeetingResponse>()?;
        Ok(meeting_res.meeting.try_into()?)
    }

    async fn edit_meeting_name(
        &self,
        meeting_id: &str,
        new_meeting_name: &str,
    ) -> Result<Meeting, HttpClientError> {
        let body = EditMeetingNameRequest {
            name: new_meeting_name.to_string(),
        };
        let req = self
            .put(format!("/meet/v1/meetings/{meeting_id}/name"))
            .body_json(body)?;
        let res = self.get_session().send(req).await?;
        let meeting_res = res.parse_response::<UpdateMeetingResponse>()?;
        Ok(meeting_res.meeting.try_into()?)
    }

    async fn update_meeting_schedule(
        &self,
        meeting_id: &str,
        params: UpdateMeetingScheduleParams,
    ) -> Result<Meeting, HttpClientError> {
        let body: UpdateMeetingScheduleRequest = params.into();
        let req = self
            .put(format!("/meet/v1/meetings/{meeting_id}/schedule"))
            .body_json(body)?;
        let res = self.get_session().send(req).await?;
        let meeting_res = res.parse_response::<UpdateMeetingResponse>()?;
        Ok(meeting_res.meeting.try_into()?)
    }

    async fn rotate_personal_meeting(
        &self,
        meeting: CreateMeetingParams,
    ) -> Result<Meeting, HttpClientError> {
        let body: CreateMeetingRequest = meeting.into();
        let req = self
            .post("/meet/v1/meetings/personal/rotate")
            .body_json(body)?;
        let res = self.get_session().send(req).await?;
        let meeting_res = res.parse_response::<CreateMeetingResponse>()?;
        Ok(meeting_res.meeting.try_into()?)
    }

    async fn end_meeting(
        &self,
        meeting_name: &str,
        access_token: &str,
    ) -> Result<(), HttpClientError> {
        let req = self
            .post(format!("/meet/v1/meetings/links/{meeting_name}/end"))
            .body_json(EndMeetingRequest {
                access_token: access_token.to_string(),
            })?;
        self.get_session().send(req).await?;
        Ok(())
    }

    async fn delete_meeting(&self, meeting_id: &str) -> Result<(), HttpClientError> {
        let req = self.delete(format!("/meet/v1/meetings/{meeting_id}"));
        self.get_session().send(req).await?;
        Ok(())
    }

    async fn get_meeting_info(&self, meeting_name: &str) -> Result<MeetingInfo, HttpClientError> {
        let req = self.get(format!("/meet/v1/meetings/links/{meeting_name}"));
        let res = self.get_session().send(req).await?;
        let meeting_info_res = res.parse_response::<MeetingInfoResponse>()?;
        Ok(meeting_info_res.meeting_info.try_into()?)
    }

    async fn fetch_meeting(&self, meeting_id: &str) -> Result<Meeting, HttpClientError> {
        let req = self.get(format!("/meet/v1/meetings/{meeting_id}"));
        let res = self.get_session().send(req).await?;
        let meeting_res = res.parse_response::<FetchMeetingResponse>()?;
        Ok(meeting_res.meeting.try_into()?)
    }

    async fn lock_meeting(&self, meet_link_name: &str) -> Result<(), HttpClientError> {
        let req = self.post(format!("/meet/v1/meetings/links/{meet_link_name}/lock"));
        let res = self.get_session().send(req).await?;
        let _ = res.parse_response::<ProtonEmptyResponse>()?;
        Ok(())
    }

    async fn unlock_meeting(&self, meet_link_name: &str) -> Result<(), HttpClientError> {
        let req = self.post(format!("/meet/v1/meetings/links/{meet_link_name}/unlock"));
        let res = self.get_session().send(req).await?;
        let _ = res.parse_response::<ProtonEmptyResponse>()?;
        Ok(())
    }
}
