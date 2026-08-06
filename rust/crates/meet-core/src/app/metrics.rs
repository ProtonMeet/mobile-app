use super::App;
use crate::domain::user::ports::UserService;
use crate::errors::core::MeetCoreError;
use crate::infra::dto::realtime::{
    ConnectionLostMetric, DesignatedCommitterMetric, ErrorCodeMetric, RejoinReason,
    ServiceMetricsRequest, UserEpochHealthMetric, UserJoinTimeMetric, UserRejoinMetric,
    UserRetryCountMetric,
};

impl App {
    async fn metrics_app_version_and_user_agent(&self) -> Result<(String, String), MeetCoreError> {
        let app_state = self.state.read().await;
        let app_version = app_state
            .app_version
            .as_ref()
            .ok_or_else(|| MeetCoreError::InternalError {
                message: "app_version not set".to_string(),
                details: None,
            })?
            .clone();
        let user_agent = app_state
            .user_agent
            .as_ref()
            .ok_or_else(|| MeetCoreError::InternalError {
                message: "user_agent not set".to_string(),
                details: None,
            })?
            .clone();
        Ok((app_version, user_agent))
    }

    pub async fn log_start_to_join_room(&self) -> Result<(), MeetCoreError> {
        let mut state = self.state.write().await;
        state.total_join_start_time = Some(crate::utils::instant::now());
        Ok(())
    }

    /// Log metrics when room join is successful, this method must be called right after the room is showing to user on client side
    pub async fn log_joined_room(
        &self,
        is_vp9_decode_supported: Option<bool>,
        is_vp9_encode_supported: Option<bool>,
    ) -> Result<(), MeetCoreError> {
        let state = self.state.read().await;
        let join_start_time =
            state
                .join_start_time
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "join_start_time not set".to_string(),
                    details: None,
                })?;

        let total_join_start_time =
            state
                .total_join_start_time
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "total_join_start_time not set".to_string(),
                    details: None,
                })?;

        let join_mls_time_ms = state
            .join_mls_time
            .map(|mls_time| {
                // Calculate duration between join_start_time and mls_time
                // Since we can't directly subtract two Instants, we calculate:
                // (current_time - join_start_time) - (current_time - mls_time) = mls_time - join_start_time
                let total_elapsed = join_start_time.elapsed();
                let mls_elapsed = mls_time.elapsed();
                if total_elapsed >= mls_elapsed {
                    (total_elapsed - mls_elapsed).as_millis() as u64
                } else {
                    0
                }
            })
            .unwrap_or(0);

        let join_type = state.join_type;
        let is_waiting_room_enabled = state.used_waiting_room_for_join;

        drop(state);

        let join_room_time_ms = join_start_time.elapsed().as_millis() as u64;
        let total_join_time_ms = total_join_start_time.elapsed().as_millis() as u64;

        // Get MLS retry count from Service
        let mls_retry_count = self.user_service.read().await.get_mls_retry_count().await;

        // Get user_id and room_id
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);

        // Get base64_sd_kbt for authorization
        let base64_sd_kbt = self
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: format!("Failed to get sd_kbt: {e}"),
                details: None,
            })?;

        // Get app_version and user_agent from state
        let (app_version, user_agent) = {
            let app_state = self.state.read().await;
            let app_version = app_state
                .app_version
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "app_version not set".to_string(),
                    details: None,
                })?
                .clone();
            let user_agent = app_state
                .user_agent
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "user_agent not set".to_string(),
                    details: None,
                })?
                .clone();
            (app_version, user_agent)
        };

        // Build metrics request
        let metrics_request = ServiceMetricsRequest {
            user_join_time: Some(UserJoinTimeMetric {
                is_waiting_room_enabled: Some(false),
                room_join_time_ms: join_room_time_ms,
                mls_join_time_ms: join_mls_time_ms,
                join_type,
                is_vp9_decode_supported,
                is_vp9_encode_supported,
                total_join_time_ms: Some(total_join_time_ms),
            }),
            user_retry_count: Some(UserRetryCountMetric {
                retry_count: mls_retry_count,
            }),
            error_code: None,
            connection_lost: None,
            user_epoch_health: None,
            designated_committer: None,
            user_rejoin: None,
        };

        // Send metrics
        self.mls_api
            .send_metrics(&base64_sd_kbt, &app_version, &user_agent, &metrics_request)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            })?;

        Ok(())
    }

    /// Log metrics when room join fails, this method must be called right after the room join fails on client side
    pub async fn log_joined_room_failed(
        &self,
        error_code: Option<String>,
    ) -> Result<(), MeetCoreError> {
        let state = self.state.read().await;
        let join_start_time =
            state
                .join_start_time
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "join_start_time not set".to_string(),
                    details: None,
                })?;

        let total_join_start_time =
            state
                .total_join_start_time
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "total_join_start_time not set".to_string(),
                    details: None,
                })?;

        let join_room_time_ms = join_start_time.elapsed().as_millis() as u64;
        let total_join_time_ms = total_join_start_time.elapsed().as_millis() as u64;
        let is_waiting_room_enabled = state.used_waiting_room_for_join;
        drop(state);

        // Get MLS retry count from Service
        let mls_retry_count = self.user_service.read().await.get_mls_retry_count().await;

        // Get user_id and room_id
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);

        let (app_version, user_agent) = self.metrics_app_version_and_user_agent().await?;

        // Get base64_sd_kbt for authorization
        let base64_sd_kbt = self
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: format!("Failed to get sd_kbt: {e}"),
                details: None,
            })?;

        // Build metrics request with error
        let metrics_request = ServiceMetricsRequest {
            user_join_time: Some(UserJoinTimeMetric {
                is_waiting_room_enabled: None,
                room_join_time_ms: join_room_time_ms,
                mls_join_time_ms: join_room_time_ms,
                join_type: None,
                is_vp9_decode_supported: None,
                is_vp9_encode_supported: None,
                total_join_time_ms: Some(total_join_time_ms),
            }),
            user_retry_count: Some(UserRetryCountMetric {
                retry_count: mls_retry_count,
            }),
            error_code: error_code.map(|code| ErrorCodeMetric {
                error_code: code,
                error_message: None,
            }),
            connection_lost: None,
            user_epoch_health: None,
            designated_committer: None,
            user_rejoin: None,
        };

        // Send metrics
        self.mls_api
            .send_metrics(&base64_sd_kbt, &app_version, &user_agent, &metrics_request)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            })?;

        Ok(())
    }

    pub async fn log_connection_lost(&self) -> Result<(), MeetCoreError> {
        // Get user_id and room_id
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);
        // Get base64_sd_kbt for authorization
        let base64_sd_kbt = self
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: format!("Failed to get sd_kbt: {e}"),
                details: None,
            })?;

        // Get metrics from ServiceState (recorded by is_mls_up_to_date)
        let mls_sync_metrics = self
            .user_service
            .read()
            .await
            .get_mls_sync_metrics()
            .await
            .ok_or_else(|| MeetCoreError::InternalError {
                message: "MLS sync metrics not available".to_string(),
                details: None,
            })?;

        // Get RTT via ping
        let rtt = self.ping().await.unwrap_or(0) as u32;

        // Get app_version and user_agent from state
        let (app_version, user_agent) = {
            let app_state = self.state.read().await;
            let app_version = app_state
                .app_version
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "app_version not set".to_string(),
                    details: None,
                })?
                .clone();
            let user_agent = app_state
                .user_agent
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "user_agent not set".to_string(),
                    details: None,
                })?
                .clone();
            (app_version, user_agent)
        };

        let metrics_request = ServiceMetricsRequest {
            user_join_time: None,
            user_retry_count: None,
            error_code: None,
            connection_lost: Some(ConnectionLostMetric {
                local_epoch: mls_sync_metrics.local_epoch,
                server_epoch: mls_sync_metrics.server_epoch,
                is_user_device_in_group_info: mls_sync_metrics.is_user_device_in_group_info,
                is_websocket_disconnected: mls_sync_metrics.is_websocket_disconnected,
                has_websocket_reconnected: mls_sync_metrics.has_websocket_reconnected,
                rtt,
                is_get_group_info_success: mls_sync_metrics.is_get_group_info_success,
                connection_lost_type: mls_sync_metrics.connection_lost_type,
            }),
            user_epoch_health: None,
            designated_committer: None,
            user_rejoin: None,
        };
        self.mls_api
            .send_metrics(&base64_sd_kbt, &app_version, &user_agent, &metrics_request)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            })?;

        Ok(())
    }

    /// Log user epoch health metrics, the current_epoch and epoch_display_code will be passed from client side
    pub async fn log_user_epoch_health(
        &self,
        current_epoch: u32,
        epoch_display_code: String,
    ) -> Result<(), MeetCoreError> {
        // Get user_id and meeting_id
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);

        let (app_version, user_agent) = self.metrics_app_version_and_user_agent().await?;

        // Get base64_sd_kbt for authorization
        let base64_sd_kbt = self
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: format!("Failed to get sd_kbt: {e}"),
                details: None,
            })?;
        // Get RTT via ping
        let rtt = self.ping().await.unwrap_or(0) as u32;

        // websocket_rtt is not available, set to None
        let websocket_rtt = self.ws_client.get_last_rtt_ms().await;

        // Build metrics request
        let metrics_request = ServiceMetricsRequest {
            user_join_time: None,
            user_retry_count: None,
            error_code: None,
            connection_lost: None,
            user_epoch_health: Some(UserEpochHealthMetric {
                local_epoch: current_epoch,
                epoch_authenticator: Some(epoch_display_code),
                rtt,
                websocket_rtt,
            }),
            designated_committer: None,
            user_rejoin: None,
        };

        // Send metrics
        self.mls_api
            .send_metrics(&base64_sd_kbt, &app_version, &user_agent, &metrics_request)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            })?;

        Ok(())
    }

    /// Try to log designated committer metrics, if this client is not the committer for this epoch, do nothing
    pub async fn try_log_designated_committer(&self, epoch: u32) -> Result<(), MeetCoreError> {
        // Get user_id and meeting_id
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);

        let mls_designated_committer_metrics = self
            .user_service
            .read()
            .await
            .get_mls_designated_committer_metrics_at_epoch(epoch)
            .await;

        let Some(designated_committer_metrics) = mls_designated_committer_metrics else {
            return Ok(());
        };

        if !designated_committer_metrics.is_committer {
            return Ok(());
        }

        // Get base64_sd_kbt for authorization
        let base64_sd_kbt = self
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: format!("Failed to get sd_kbt: {e}"),
                details: None,
            })?;

        // Get app_version and user_agent from state
        let (app_version, user_agent) = {
            let app_state = self.state.read().await;
            let app_version = app_state
                .app_version
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "app_version not set".to_string(),
                    details: None,
                })?
                .clone();
            let user_agent = app_state
                .user_agent
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "user_agent not set".to_string(),
                    details: None,
                })?
                .clone();
            (app_version, user_agent)
        };

        // Build metrics request
        let metrics_request = ServiceMetricsRequest {
            user_join_time: None,
            user_retry_count: None,
            error_code: None,
            connection_lost: None,
            user_epoch_health: None,
            designated_committer: Some(DesignatedCommitterMetric {
                epoch,
                designated_committer_rank: designated_committer_metrics.rank,
                new_member_count: designated_committer_metrics.new_member_count,
                removed_member_count: designated_committer_metrics.removed_member_count,
            }),
            user_rejoin: None,
        };

        // Send metrics
        self.mls_api
            .send_metrics(&base64_sd_kbt, &app_version, &user_agent, &metrics_request)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            })?;

        Ok(())
    }

    /// Log user rejoin metrics, parameters will be passed from client side
    pub async fn log_user_rejoin(
        &self,
        rejoin_time_ms: u64,
        incremental_count: u32,
        reason: RejoinReason,
        success: bool,
    ) -> Result<(), MeetCoreError> {
        // Get user_id and meeting_id
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);

        // Get base64_sd_kbt for authorization
        let base64_sd_kbt = self
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: format!("Failed to get sd_kbt: {e}"),
                details: None,
            })?;

        // Get app_version and user_agent from state
        let (app_version, user_agent) = {
            let app_state = self.state.read().await;
            let app_version = app_state
                .app_version
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "app_version not set".to_string(),
                    details: None,
                })?
                .clone();
            let user_agent = app_state
                .user_agent
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "user_agent not set".to_string(),
                    details: None,
                })?
                .clone();
            (app_version, user_agent)
        };

        // Build metrics request
        let metrics_request = ServiceMetricsRequest {
            user_join_time: None,
            user_retry_count: None,
            error_code: None,
            connection_lost: None,
            user_epoch_health: None,
            designated_committer: None,
            user_rejoin: Some(UserRejoinMetric {
                rejoin_time_ms,
                incremental_count,
                reason,
                success,
            }),
        };

        // Send metrics
        self.mls_api
            .send_metrics(&base64_sd_kbt, &app_version, &user_agent, &metrics_request)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            })?;

        Ok(())
    }
}
