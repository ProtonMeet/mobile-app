use std::collections::{BTreeMap, HashMap};

pub struct MlsMessageCache {
    // room_id -> epoch -> message_type -> messages
    pub messages: HashMap<String, BTreeMap<u64, HashMap<CachedMessageType, Vec<CachedMlsMessage>>>>,
}

impl Default for MlsMessageCache {
    fn default() -> Self {
        Self::new()
    }
}

impl MlsMessageCache {
    pub fn new() -> Self {
        Self {
            messages: HashMap::new(),
        }
    }

    pub fn cache_message(
        &mut self,
        room_id: String,
        epoch: u64,
        message_type: CachedMessageType,
        message: mls_types::MlsMessage,
    ) {
        let cached_message = CachedMlsMessage {
            message,
            room_id: room_id.clone(),
            epoch,
        };

        self.messages
            .entry(room_id)
            .or_default()
            .entry(epoch)
            .or_default()
            .entry(message_type)
            .or_default()
            .push(cached_message);
    }

    /// Get all cached messages for a specific room and epoch, ordered for processing
    /// Returns (MessageType, Message) pairs with proposals first, then commits
    pub fn get_messages_for_epoch(
        &self,
        room_id: &str,
        epoch: u64,
    ) -> Option<Vec<(CachedMessageType, CachedMlsMessage)>> {
        let room_messages = self.messages.get(room_id)?;
        let epoch_messages = room_messages.get(&epoch)?;

        let mut all_messages = Vec::new();

        // Process proposals first, then commits
        if let Some(proposals) = epoch_messages.get(&CachedMessageType::Proposal) {
            for proposal in proposals {
                all_messages.push((CachedMessageType::Proposal, proposal.clone()));
            }
        }
        if let Some(commits) = epoch_messages.get(&CachedMessageType::Commit) {
            for commit in commits {
                all_messages.push((CachedMessageType::Commit, commit.clone()));
            }
        }

        Some(all_messages)
    }

    /// Get all processable epochs for a room (epochs <= current_epoch)
    pub fn get_processable_epochs(&self, room_id: &str, current_epoch: u64) -> Vec<u64> {
        self.messages
            .get(room_id)
            .map(|room_messages| {
                room_messages
                    .keys()
                    .filter(|&&epoch| epoch <= current_epoch)
                    .cloned()
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Remove processed messages for a specific room and epoch
    pub fn remove_processed_messages(&mut self, room_id: &str, epoch: u64) {
        if let Some(room_messages) = self.messages.get_mut(room_id) {
            room_messages.remove(&epoch);
            if room_messages.is_empty() {
                self.messages.remove(room_id);
            }
        }
    }

    /// Clean up old cached messages (epochs < ( current_epoch - 1) - threshold)
    pub fn cleanup_old_messages(&mut self, room_id: &str, current_epoch: u64, threshold: u64) {
        if let Some(room_messages) = self.messages.get_mut(room_id) {
            let cutoff_epoch = current_epoch.saturating_sub(1).saturating_sub(threshold);
            room_messages.retain(|&epoch, _| epoch > cutoff_epoch);
            if room_messages.is_empty() {
                self.messages.remove(room_id);
            }
        }
    }
}

#[derive(Debug, Clone)]
pub struct CachedMlsMessage {
    pub message: mls_types::MlsMessage,
    pub room_id: String,
    pub epoch: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum CachedMessageType {
    Proposal,
    Commit,
}
