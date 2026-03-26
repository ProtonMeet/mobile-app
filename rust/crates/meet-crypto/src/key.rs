/// Key type that matches meet-core domain Key structure
/// This allows meet-crypto to work with keys without depending on meet-core
#[derive(Debug, Clone)]
pub struct Key {
    pub id: String,
    pub private_key: String,
    pub token: Option<String>,
    pub signature: Option<String>,
    pub primary: bool,
    pub active: bool,
}
