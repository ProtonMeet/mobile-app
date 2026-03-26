use serde::Serialize;
use uuid::Uuid;

pub use meet_type::{
    UnknownWebSocketCommand, WebSocketTextRequest, WebSocketTextRequestCommand,
    WebSocketTextResponse, WebSocketTextResponseCommand,
};

#[derive(Serialize)]
pub struct ClientAck {
    #[serde(rename = "type")]
    pub msg_type: String, // "ack"
    #[serde(with = "uuid::serde::compact")]
    pub id: Uuid,
}
