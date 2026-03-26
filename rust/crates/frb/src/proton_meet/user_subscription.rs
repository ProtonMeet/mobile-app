use flutter_rust_bridge::frb;
use proton_meet_common::models::{
    can_pay as can_pay_impl, get_user_byte as get_user_byte_impl,
    has_paid_drive as has_paid_drive_impl, has_paid_lumo as has_paid_lumo_impl,
    has_paid_mail as has_paid_mail_impl, has_paid_meet as has_paid_meet_impl,
    has_paid_pass as has_paid_pass_impl, has_paid_vpn as has_paid_vpn_impl,
    has_paid_wallet as has_paid_wallet_impl, has_pass_lifetime as has_pass_lifetime_impl,
    has_pass_lifetime_or_via_simple_login as has_pass_lifetime_or_via_simple_login_impl,
    has_pass_via_simple_login as has_pass_via_simple_login_impl, is_admin as is_admin_impl,
    is_delinquent as is_delinquent_impl, is_free as is_free_impl, is_member as is_member_impl,
    is_paid as is_paid_impl, is_private as is_private_impl, is_self as is_self_impl, ProtonUser,
};

/// Check if user has paid Mail subscription
#[frb(sync)]
pub fn has_paid_mail(user: &ProtonUser) -> bool {
    has_paid_mail_impl(user)
}

/// Check if user has paid Drive subscription
#[frb(sync)]
pub fn has_paid_drive(user: &ProtonUser) -> bool {
    has_paid_drive_impl(user)
}

/// Check if user has paid Wallet subscription
#[frb(sync)]
pub fn has_paid_wallet(user: &ProtonUser) -> bool {
    has_paid_wallet_impl(user)
}

/// Check if user has paid VPN subscription
#[frb(sync)]
pub fn has_paid_vpn(user: &ProtonUser) -> bool {
    has_paid_vpn_impl(user)
}

/// Check if user has Pass lifetime flag
#[frb(sync)]
pub fn has_pass_lifetime(user: &ProtonUser) -> bool {
    has_pass_lifetime_impl(user)
}

/// Check if user has Pass via SimpleLogin flag
#[frb(sync)]
pub fn has_pass_via_simple_login(user: &ProtonUser) -> bool {
    has_pass_via_simple_login_impl(user)
}

/// Check if user has paid Pass subscription (including lifetime or SimpleLogin)
#[frb(sync)]
pub fn has_paid_pass(user: &ProtonUser) -> bool {
    has_paid_pass_impl(user)
}

/// Check if user has Pass lifetime or via SimpleLogin
#[frb(sync)]
pub fn has_pass_lifetime_or_via_simple_login(user: &ProtonUser) -> bool {
    has_pass_lifetime_or_via_simple_login_impl(user)
}

/// Check if user has paid Lumo subscription
#[frb(sync)]
pub fn has_paid_lumo(user: &ProtonUser) -> bool {
    has_paid_lumo_impl(user)
}

/// Check if user has paid Meet subscription
#[frb(sync)]
pub fn has_paid_meet(user: &ProtonUser) -> bool {
    has_paid_meet_impl(user)
}

/// Check if user is paid (has any subscription)
#[frb(sync)]
pub fn is_paid(user: &ProtonUser) -> bool {
    is_paid_impl(user)
}

/// Check if user is private
#[frb(sync)]
pub fn is_private(user: &ProtonUser) -> bool {
    is_private_impl(user)
}

/// Check if user is free (no subscription)
#[frb(sync)]
pub fn is_free(user: &ProtonUser) -> bool {
    is_free_impl(user)
}

/// Check if user is admin
#[frb(sync)]
pub fn is_admin(user: &ProtonUser) -> bool {
    is_admin_impl(user)
}

/// Check if user is member
#[frb(sync)]
pub fn is_member(user: &ProtonUser) -> bool {
    is_member_impl(user)
}

/// Check if user is self (not delegated access)
#[frb(sync)]
pub fn is_self(user: &ProtonUser) -> bool {
    is_self_impl(user)
}

/// Check if user is delinquent
#[frb(sync)]
pub fn is_delinquent(user: &ProtonUser) -> bool {
    is_delinquent_impl(user)
}

/// Check if user can pay (admin or free role)
#[frb(sync)]
pub fn can_pay(user: &ProtonUser) -> bool {
    can_pay_impl(user)
}

/// Get user byte from base64url encoded user ID
#[frb(sync)]
pub fn get_user_byte(user: &ProtonUser) -> Option<u8> {
    get_user_byte_impl(user)
}
