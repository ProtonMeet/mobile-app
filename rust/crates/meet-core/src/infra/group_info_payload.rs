use base64::Engine;
use serde::Serialize;
use thiserror::Error;

pub const GROUP_INFO_ZSTD_LEVEL: i32 = 3;

#[derive(Debug, Error)]
pub enum GroupInfoPayloadError {
    #[error("Failed to serialize group info request: {0}")]
    Serialize(#[from] serde_json::Error),
    #[error("Failed to compress group info payload: {0}")]
    Compress(String),
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct UpdateGroupInfoRequest {
    pub data: Vec<u8>,
    pub commit_data: Option<Vec<u8>>,
    pub proposals: Option<Vec<Vec<u8>>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct PhpWaitingRoomDataField {
    pub data: String,
}

pub fn serialize_update_group_info_request(
    request: &UpdateGroupInfoRequest,
) -> Result<Vec<u8>, GroupInfoPayloadError> {
    Ok(serde_json::to_vec(request)?)
}

pub fn compress_group_info_json(json: &[u8]) -> Result<Vec<u8>, GroupInfoPayloadError> {
    zstd::bulk::compress(json, GROUP_INFO_ZSTD_LEVEL)
        .map_err(|e| GroupInfoPayloadError::Compress(format!("Failed to compress request: {e}")))
}

pub fn encode_php_waiting_room_data_field(
    inner_json: &[u8],
) -> Result<PhpWaitingRoomDataField, GroupInfoPayloadError> {
    let compressed = compress_group_info_json(inner_json)?;
    Ok(PhpWaitingRoomDataField {
        data: base64::engine::general_purpose::STANDARD.encode(compressed),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn php_waiting_room_body_is_base64_of_zstd_json() {
        let inner = br#"{"Data":[1,2],"CommitData":[3,4]}"#;
        let body = encode_php_waiting_room_data_field(inner).unwrap();
        let decoded = base64::engine::general_purpose::STANDARD
            .decode(&body.data)
            .unwrap();
        let json = zstd::bulk::decompress(&decoded, 1024 * 1024).unwrap();
        assert_eq!(json, inner);
    }
}
