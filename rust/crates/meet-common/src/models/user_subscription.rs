use crate::models::{product_bit::ProductBit, ProtonUser};

/// Role constants
pub const ADMIN_ROLE: u32 = 1;
pub const MEMBER_ROLE: u32 = 2;
pub const FREE_ROLE: u32 = 0;

/// Check if a bit is set in the subscribed value
pub fn has_bit(subscribed: u32, bit: ProductBit) -> bool {
    (subscribed & bit.value()) != 0
}

/// Check if user has paid Mail subscription
pub fn has_paid_mail(user: &ProtonUser) -> bool {
    has_bit(user.subscribed, ProductBit::Mail)
}

/// Check if user has paid Drive subscription
pub fn has_paid_drive(user: &ProtonUser) -> bool {
    has_bit(user.subscribed, ProductBit::Drive)
}

/// Check if user has paid Wallet subscription
pub fn has_paid_wallet(user: &ProtonUser) -> bool {
    has_bit(user.subscribed, ProductBit::Wallet)
}

/// Check if user has paid VPN subscription
pub fn has_paid_vpn(user: &ProtonUser) -> bool {
    has_bit(user.subscribed, ProductBit::Vpn)
}

/// Check if user has Pass lifetime flag
pub fn has_pass_lifetime(user: &ProtonUser) -> bool {
    user.flags
        .as_ref()
        .and_then(|flags| flags.get("pass-lifetime"))
        .copied()
        .unwrap_or(false)
}

/// Check if user has Pass via SimpleLogin flag
pub fn has_pass_via_simple_login(user: &ProtonUser) -> bool {
    user.flags
        .as_ref()
        .and_then(|flags| flags.get("pass-from-sl"))
        .copied()
        .unwrap_or(false)
}

/// Check if user has paid Pass subscription (including lifetime or SimpleLogin)
pub fn has_paid_pass(user: &ProtonUser) -> bool {
    has_bit(user.subscribed, ProductBit::Pass)
        || has_pass_lifetime(user)
        || has_pass_via_simple_login(user)
}

/// Check if user has Pass lifetime or via SimpleLogin
pub fn has_pass_lifetime_or_via_simple_login(user: &ProtonUser) -> bool {
    has_pass_lifetime(user) || has_pass_via_simple_login(user)
}

/// Check if user has paid Lumo subscription
pub fn has_paid_lumo(user: &ProtonUser) -> bool {
    has_bit(user.subscribed, ProductBit::Lumo)
}

/// Check if user has paid Meet subscription
pub fn has_paid_meet(user: &ProtonUser) -> bool {
    has_bit(user.subscribed, ProductBit::Meet)
}

/// Check if user is paid (has any subscription)
pub fn is_paid(user: &ProtonUser) -> bool {
    user.subscribed != 0
}

/// Check if user is private
pub fn is_private(user: &ProtonUser) -> bool {
    user.private == 1
}

/// Check if user is free (no subscription)
pub fn is_free(user: &ProtonUser) -> bool {
    !is_paid(user)
}

/// Check if user is admin
pub fn is_admin(user: &ProtonUser) -> bool {
    user.role == ADMIN_ROLE
}

/// Check if user is member
pub fn is_member(user: &ProtonUser) -> bool {
    user.role == MEMBER_ROLE
}

/// Check if user is self (not delegated access)
pub fn is_self(user: &ProtonUser) -> bool {
    user.organization_private_key.is_none()
        && !user
            .flags
            .as_ref()
            .and_then(|flags| flags.get("delegated-access"))
            .copied()
            .unwrap_or(false)
}

/// Check if user is delinquent
pub fn is_delinquent(user: &ProtonUser) -> bool {
    user.delinquent != 0
}

/// Check if user can pay (admin or free role)
pub fn can_pay(user: &ProtonUser) -> bool {
    user.role == ADMIN_ROLE || user.role == FREE_ROLE
}

/// Get user byte from base64url encoded user ID
pub fn get_user_byte(user: &ProtonUser) -> Option<u8> {
    use base64::Engine;
    // Decode base64url
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(&user.id)
        .ok()?;
    decoded.first().copied()
}
