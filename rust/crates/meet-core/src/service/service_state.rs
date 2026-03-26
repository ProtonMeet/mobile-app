use crate::infra::dto::realtime::{ConnectionLostType, MlsWelcomeInfo};
use crate::utils::unix_timestamp_ms;
use std::collections::HashMap;
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MlsGroupState {
    Success,
    WaitingForJoinProposalWelcome,
    Pending,
    ServerVersionNotSupported,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MlsSyncState {
    Success,  // MLS sync check success
    Checking, // MLS sync check is in progress, didnt trigger websocket reconnection yet
    Retrying, // retrying, had triggered websocket reconnection, client should display warning banner for this state
    Failed,   // MLS sync failed, client should start full reconnection flow
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct LivekitUUIDInfo {
    pub uuid: Uuid,
    pub last_seen: u64, // timestamp in milliseconds
}

#[derive(Debug, Clone)]
pub struct MlsSyncMetrics {
    pub local_epoch: u32,
    pub server_epoch: u32,
    pub is_user_device_in_group_info: bool,
    pub is_websocket_disconnected: bool,
    pub has_websocket_reconnected: bool,
    pub is_get_group_info_success: bool,
    pub connection_lost_type: Option<ConnectionLostType>,
}

#[derive(Debug, Clone)]
pub struct MLSDesignatedCommitterMetrics {
    pub new_epoch: u32,
    pub is_committer: bool,
    pub rank: u64,
    pub new_member_count: Option<u32>,
    pub removed_member_count: Option<u32>,
}

#[derive(Debug)]
pub struct ServiceState {
    pub mls_group_state: MlsGroupState,
    pub mls_sync_state: MlsSyncState,
    pub welcome_info: Option<MlsWelcomeInfo>,
    pub livekit_active_uuid_hashset: Option<HashMap<Uuid, LivekitUUIDInfo>>,
    pub last_livekit_active_uuid_update_time: u64,
    pub mls_retry_count: u32,
    pub mls_sync_metrics: Option<MlsSyncMetrics>,
    pub mls_designated_committer_metrics: HashMap<u32, MLSDesignatedCommitterMetrics>,
    pub last_offline_members_handled_epoch: Option<u64>,
    pub last_host_role_update_proposal_epoch: Option<u64>,
}

impl Default for ServiceState {
    fn default() -> Self {
        Self::new()
    }
}

impl ServiceState {
    pub fn new() -> Self {
        Self {
            mls_group_state: MlsGroupState::Pending,
            mls_sync_state: MlsSyncState::Checking,
            welcome_info: None,
            livekit_active_uuid_hashset: None,
            last_livekit_active_uuid_update_time: 0,
            mls_retry_count: 0,
            mls_sync_metrics: None,
            mls_designated_committer_metrics: HashMap::new(),
            last_offline_members_handled_epoch: None,
            last_host_role_update_proposal_epoch: None,
        }
    }

    pub fn set_mls_group_state(&mut self, mls_group_state: MlsGroupState) {
        self.mls_group_state = mls_group_state;
    }

    pub fn set_mls_sync_state(&mut self, mls_sync_state: MlsSyncState) {
        self.mls_sync_state = mls_sync_state;
    }

    pub fn get_mls_sync_state(&self) -> MlsSyncState {
        self.mls_sync_state.clone()
    }

    pub fn set_welcome_info(&mut self, welcome_info: Option<MlsWelcomeInfo>) {
        self.welcome_info = welcome_info;
    }
    pub fn get_welcome_info(&self) -> Option<MlsWelcomeInfo> {
        self.welcome_info.clone()
    }
    pub fn clear_welcome_info(&mut self) {
        self.welcome_info = None;
    }

    pub fn set_livekit_active_uuids(&mut self, livekit_active_uuid_list: Vec<String>) {
        let current_time = unix_timestamp_ms();
        let mut updated_hashmap = self.livekit_active_uuid_hashset.take().unwrap_or_default();

        for uuid_str in livekit_active_uuid_list.iter() {
            if let Ok(uuid) = Uuid::parse_str(uuid_str.as_str()) {
                updated_hashmap.insert(
                    uuid,
                    LivekitUUIDInfo {
                        uuid,
                        last_seen: current_time,
                    },
                );
            }
        }

        self.livekit_active_uuid_hashset = Some(updated_hashmap);
        self.last_livekit_active_uuid_update_time = current_time;
    }

    pub fn get_livekit_active_uuid_hashmap(&self) -> HashMap<Uuid, LivekitUUIDInfo> {
        self.livekit_active_uuid_hashset.clone().unwrap_or_default()
    }

    pub fn clear_livekit_active_uuid_hashset(&mut self) {
        self.livekit_active_uuid_hashset = None;
    }

    pub fn set_mls_sync_metrics(&mut self, metrics: MlsSyncMetrics) {
        self.mls_sync_metrics = Some(metrics);
    }

    pub fn get_mls_sync_metrics(&self) -> Option<MlsSyncMetrics> {
        self.mls_sync_metrics.clone()
    }

    pub fn set_mls_designated_committer_metrics(
        &mut self,
        new_epoch: u32,
        is_committer: bool,
        rank: u64,
    ) {
        let metrics = MLSDesignatedCommitterMetrics {
            new_epoch,
            is_committer,
            rank,
            new_member_count: None,
            removed_member_count: None,
        };
        self.mls_designated_committer_metrics
            .insert(new_epoch, metrics);
    }

    pub fn get_mls_designated_committer_metrics_at_epoch(
        &self,
        epoch: u32,
    ) -> Option<MLSDesignatedCommitterMetrics> {
        self.mls_designated_committer_metrics.get(&epoch).cloned()
    }

    pub fn has_handled_offline_members_for_epoch(&self, epoch: u64) -> bool {
        self.last_offline_members_handled_epoch
            .map(|handled_epoch| handled_epoch >= epoch)
            .unwrap_or(false)
    }

    pub fn mark_offline_members_handled_for_epoch(&mut self, epoch: u64) {
        self.last_offline_members_handled_epoch = Some(epoch);
    }

    pub fn has_sent_host_role_update_for_epoch(&self, epoch: u64) -> bool {
        self.last_host_role_update_proposal_epoch
            .map(|sent_epoch| sent_epoch >= epoch)
            .unwrap_or(false)
    }

    pub fn mark_host_role_update_sent_for_epoch(&mut self, epoch: u64) {
        self.last_host_role_update_proposal_epoch = Some(epoch);
    }

    pub fn reset(&mut self) {
        self.mls_group_state = MlsGroupState::Pending;
        self.mls_sync_state = MlsSyncState::Checking;
        self.welcome_info = None;
        self.livekit_active_uuid_hashset = None;
        self.mls_retry_count = 0;
        self.mls_sync_metrics = None;
        self.mls_designated_committer_metrics.clear();
        self.last_offline_members_handled_epoch = None;
        self.last_host_role_update_proposal_epoch = None;
    }
}
