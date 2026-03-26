/// Product bit flags for subscription checking
/// Should be synced with ProductGroup in API
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProductBit {
    Mail = 1,
    Drive = 2,
    Vpn = 4,
    Pass = 8,
    Wallet = 16,
    Lumo = 64,
    Meet = 256,
}

impl ProductBit {
    pub fn value(&self) -> u32 {
        *self as u32
    }
}

/// Product enum for reference
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Product {
    Mail = 1,
    Vpn = 2,
    Calendar = 3,
    Drive = 4,
    Pass = 5,
    Wallet = 6,
    Lumo = 9,
    Authenticator = 10,
}

impl Product {
    pub fn value(&self) -> u32 {
        *self as u32
    }
}
