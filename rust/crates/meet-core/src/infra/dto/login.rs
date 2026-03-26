use serde::{Deserialize, Serialize};

use crate::domain::user::models::login::Modulus;

// #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
// pub struct LoginResponse {
//     pub user_id: String,
//     pub user_mail: String,
//     pub user_name: String,
//     pub mailbox_password: String,
// }

// impl From<LoginResponse> for User {
//     fn from(login_response: LoginResponse) -> Self {
//         User {
//             id: UserId::new(login_response.user_id),
//             name: login_response.user_name,
//             email: login_response.user_mail,
//         }
//     }
// }

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct GetModulusResponse {
    pub modulus: String,
    #[serde(rename = "ModulusID")]
    pub modulus_id: String,
}

impl From<GetModulusResponse> for Modulus {
    fn from(get_modulus_response: GetModulusResponse) -> Self {
        Modulus {
            modulus_id: get_modulus_response.modulus_id,
            modulus: get_modulus_response.modulus,
        }
    }
}
