#[derive(Debug)]
pub struct UnleashResponse {
    pub status_code: u16,
    pub body: Vec<u8>,
}
