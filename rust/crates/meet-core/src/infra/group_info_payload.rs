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
pub struct WaitingRoomSettingRequest {
    pub data: Vec<u8>,
    pub commit_data: Vec<u8>,
    pub waiting_room: u8,
}

impl WaitingRoomSettingRequest {
    pub fn new(data: Vec<u8>, commit_data: Vec<u8>, enable: bool) -> Self {
        Self {
            data,
            commit_data,
            waiting_room: u8::from(enable),
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct PhpWaitingRoomDataField {
    pub data: Option<String>,
    pub waiting_room: u8,
}

pub fn serialize_group_info_payload<T: Serialize>(
    request: &T,
) -> Result<Vec<u8>, GroupInfoPayloadError> {
    Ok(serde_json::to_vec(request)?)
}

pub fn serialize_update_group_info_request(
    request: &UpdateGroupInfoRequest,
) -> Result<Vec<u8>, GroupInfoPayloadError> {
    serialize_group_info_payload(request)
}

pub fn serialize_waiting_room_setting_request(
    request: &WaitingRoomSettingRequest,
) -> Result<Vec<u8>, GroupInfoPayloadError> {
    serialize_group_info_payload(request)
}

pub fn compress_group_info_json(json: &[u8]) -> Result<Vec<u8>, GroupInfoPayloadError> {
    zstd::bulk::compress(json, GROUP_INFO_ZSTD_LEVEL)
        .map_err(|e| GroupInfoPayloadError::Compress(format!("Failed to compress request: {e}")))
}

pub fn encode_php_waiting_room_data_field(
    inner_json: &[u8],
    enable: bool,
) -> Result<PhpWaitingRoomDataField, GroupInfoPayloadError> {
    let compressed = compress_group_info_json(inner_json)?;
    Ok(PhpWaitingRoomDataField {
        data: Some(base64::engine::general_purpose::STANDARD.encode(compressed)),
        waiting_room: u8::from(enable),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn php_waiting_room_body_is_base64_of_zstd_json() {
        let inner = br#"{"Data":[1,2],"CommitData":[3,4]}"#;
        let body = encode_php_waiting_room_data_field(inner, true).unwrap();
        let decoded = base64::engine::general_purpose::STANDARD
            .decode(body.data.as_ref().unwrap())
            .unwrap();
        let json = zstd::bulk::decompress(&decoded, 1024 * 1024).unwrap();
        assert_eq!(json, inner);
    }

    #[test]
    fn waiting_room_setting_request_serializes_correctly() {
        let request = WaitingRoomSettingRequest::new(vec![1, 2, 3], vec![4, 5, 6], true);
        let json = serialize_waiting_room_setting_request(&request).unwrap();
        let json_str = String::from_utf8(json).unwrap();
        assert_eq!(
            json_str,
            r#"{"Data":[1,2,3],"CommitData":[4,5,6],"WaitingRoom":1}"#
        );
    }

    #[test]
    fn update_group_info_request_no_waiting_room_field() {
        let request = UpdateGroupInfoRequest {
            data: vec![1, 2, 3],
            commit_data: Some(vec![4, 5]),
            proposals: Some(vec![vec![6, 7]]),
        };
        let json = serialize_update_group_info_request(&request).unwrap();
        let json_str = String::from_utf8(json).unwrap();
        assert!(!json_str.contains("WaitingRoom"));
    }

    #[test]
    fn waiting_room_setting_body_round_trips_flag() {
        for (enable, expected) in [(true, 1u8), (false, 0u8)] {
            let request = WaitingRoomSettingRequest::new(vec![1], vec![2], enable);
            let inner = serialize_waiting_room_setting_request(&request).unwrap();
            let field = encode_php_waiting_room_data_field(&inner, enable).unwrap();
            let raw = base64::engine::general_purpose::STANDARD
                .decode(field.data.as_ref().unwrap())
                .unwrap();
            let json = zstd::bulk::decompress(&raw, 1024 * 1024).unwrap();
            assert!(String::from_utf8(json)
                .unwrap()
                .contains(&format!(r#""WaitingRoom":{expected}"#)));
        }
    }

    #[test]
    fn waiting_room_pre_meeting_body_serializes_null_data_and_flag() {
        let field = PhpWaitingRoomDataField {
            data: None,
            waiting_room: 1,
        };
        let json = serde_json::to_string(&field).unwrap();
        assert_eq!(json, r#"{"Data":null,"WaitingRoom":1}"#);
    }

    #[test]
    fn waiting_room_in_call_body_includes_top_level_flag() {
        let field = encode_php_waiting_room_data_field(b"{}", false).unwrap();
        let json = serde_json::to_string(&field).unwrap();
        assert!(json.starts_with(r#"{"Data":""#));
        assert!(json.ends_with(r#","WaitingRoom":0}"#));
    }
}
