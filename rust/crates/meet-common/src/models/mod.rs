mod product_bit;
mod proton_user;
mod proton_user_key;
mod user_subscription;

pub use product_bit::{Product, ProductBit};
pub use proton_user::ProtonUser;
pub use proton_user_key::ProtonUserKey;
pub use user_subscription::{
    can_pay, get_user_byte, has_bit, has_paid_drive, has_paid_lumo, has_paid_mail, has_paid_meet,
    has_paid_pass, has_paid_vpn, has_paid_wallet, has_pass_lifetime,
    has_pass_lifetime_or_via_simple_login, has_pass_via_simple_login, is_admin, is_delinquent,
    is_free, is_member, is_paid, is_private, is_self, ADMIN_ROLE, FREE_ROLE, MEMBER_ROLE,
};
