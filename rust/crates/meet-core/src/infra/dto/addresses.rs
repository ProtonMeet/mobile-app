use serde::Deserialize;

/// `GET /core/v4/addresses` — tolerate responses that omit `Addresses` or send `null`.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ApiAddressesResponse {
    #[serde(default)]
    pub addresses: Option<Vec<muon::rest::core::v4::addresses::Address>>,
}

impl ApiAddressesResponse {
    pub fn addresses(&self) -> &[muon::rest::core::v4::addresses::Address] {
        self.addresses.as_deref().unwrap_or(&[])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn deserializes_when_addresses_omitted() {
        let body = json!({ "Code": 1000 });
        let parsed: ApiAddressesResponse =
            serde_json::from_value(body).expect("missing Addresses should default to None");
        assert!(parsed.addresses().is_empty());
    }

    #[test]
    fn deserializes_when_addresses_null() {
        let body = json!({ "Addresses": null, "Code": 1000 });
        let parsed: ApiAddressesResponse = serde_json::from_value(body).expect("null Addresses");
        assert!(parsed.addresses().is_empty());
    }
}
