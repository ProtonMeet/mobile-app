use crate::error::ChatError;

pub fn extract_mls_ciphertext(data: &[u8]) -> Result<Vec<u8>, ChatError> {
    if data.first() == Some(&b'{') {
        let v: serde_json::Value =
            serde_json::from_slice(data).map_err(|e| ChatError::LegacyEnvelope(e.to_string()))?;
        let msg = v
            .get("message")
            .and_then(|m| m.as_str())
            .ok_or_else(|| ChatError::LegacyEnvelope("missing message field".into()))?;
        Ok(msg
            .chars()
            .map(|c| {
                let cp = c as u32;
                if cp > 0xFF {
                    return Err(ChatError::LegacyEnvelope(format!(
                        "non Latin-1 character U+{cp:04X}"
                    )));
                }
                Ok(cp as u8)
            })
            .collect::<Result<Vec<_>, _>>()?)
    } else {
        Ok(data.to_vec())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_mls_bytes_from_json_envelope() {
        let payload = vec![0xABu8, 0xCD];
        let latin1: String = payload.iter().map(|&b| char::from(b)).collect();
        let json = serde_json::json!({
            "type": "message",
            "id": "user-123",
            "message": latin1,
            "timestamp": 123
        });
        let out = extract_mls_ciphertext(json.to_string().as_bytes()).unwrap();
        assert_eq!(out, payload);
    }

    #[test]
    fn passes_through_raw_bytes() {
        let raw = vec![0x01, 0x02, 0x03];
        let out = extract_mls_ciphertext(&raw).unwrap();
        assert_eq!(out, raw);
    }
}
