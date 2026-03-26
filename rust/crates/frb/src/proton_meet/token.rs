use flutter_rust_bridge::frb;
use proton_meet_app::server::token::{AccessToken, VideoGrants};

use crate::errors::BridgeError;

// Token creation function
#[frb(sync)]
pub fn create_token(
    api_key: &str,
    api_secret: &str,
    identity: &str,
    name: &str,
    room: String,
) -> Result<String, BridgeError> {
    let token = AccessToken::with_api_key(&api_key, &api_secret)
        .with_identity(identity)
        .with_name(name)
        .with_grants(VideoGrants {
            room_join: true,
            room: room,
            ..Default::default()
        })
        .to_jwt()?;
    Ok(token)
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_API_KEY: &str = "xxx";
    const TEST_API_SECRET: &str = "xxx";

    #[test]
    #[ignore]
    fn test_create_token_success() {
        let result = create_token(
            TEST_API_KEY,
            TEST_API_SECRET,
            "test_user222",
            "Test User222",
            "test_room".to_string(),
        );

        assert!(result.is_ok(), "Token creation should succeed");
        let token = result.unwrap();
        assert!(!token.is_empty(), "Token should not be empty");
        println!("Token: {token}");
    }
}
