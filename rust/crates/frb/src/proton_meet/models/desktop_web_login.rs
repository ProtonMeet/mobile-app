#[derive(Debug, Clone)]
pub struct DesktopWebLoginStart {
    pub login_url: String,
    pub browser_redirect_state: String,
}
