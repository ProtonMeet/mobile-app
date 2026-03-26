#[cfg(not(target_family = "wasm"))]
use {
    proton_meet_chat::domain::models::{
        chat_content::{ChatPayload, TextMessage},
        chat_content_enc::EncryptedChatContent,
    },
    proton_meet_chat::service::default_chat_service::DefaultChatService,
    proton_meet_chat::service::default_key_provider::DefaultKeyProvider,
    proton_meet_crypto::room_key::UnlockedRoomKey,
    tokio::sync::mpsc,
    uuid::Uuid,
};

#[cfg(target_family = "wasm")]
fn main() {
    println!("WASM");
}

#[cfg(not(target_family = "wasm"))]
#[tokio::main]
async fn main() {
    use proton_meet_chat::service::default_chat_service::ChatService;

    let (tx, mut rx) = mpsc::channel::<Vec<u8>>(32);
    let key = UnlockedRoomKey::generate();
    let key_provider = DefaultKeyProvider::new(key);
    let mut chat_service = DefaultChatService::new(key_provider);

    // 1️⃣ Simulate sending a chat message
    let sender_id = Uuid::new_v4();
    let msg = ChatPayload::Message(TextMessage {
        text: "Hello".into(),
        style: None,
    });
    let encrypted = chat_service.add_clear_message(sender_id, msg).unwrap();
    tx.send(encrypted.encrypted.to_bytes()).await.unwrap();

    // 1️⃣ Simulate sending a chat message
    let sender_id_2 = Uuid::new_v4();
    let msg = ChatPayload::Message(TextMessage {
        text: "Hello 2".into(),
        style: None,
    });
    let encrypted = chat_service.add_clear_message(sender_id_2, msg).unwrap();
    tx.send(encrypted.encrypted.to_bytes()).await.unwrap();

    let mut count = 2;
    // 3️⃣ Receiver processes incoming data
    while let Some(payload) = rx.recv().await {
        let encrypted = EncryptedChatContent::from_bytes(&payload).unwrap();
        let sender_id_test = Uuid::new_v4();
        // let decrypted = chat_service.decrypt_message(&encrypted);
        let decrypted = chat_service
            .add_encrypted_message(sender_id_test, encrypted)
            .unwrap();
        println!("Decrypted: {decrypted:?}");
        count -= 1;
        if count == 0 {
            break;
        }
    }
    // Print out chat history
    println!("----------------------------------------");
    println!("Chat history:");
    let history = chat_service.history();
    for msg in history {
        println!(
            "  sender_id: {:?}, Message: {:?}",
            msg.sender_id, msg.decrypted
        );
    }
}
