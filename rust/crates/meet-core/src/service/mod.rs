// Application Service (orchestrator) for the meet application

mod services_bundle;

pub mod message_service;
// forder name is same with module name, ignore for now and refactor later
#[allow(clippy::module_inception)]
pub mod service;
pub mod service_state;
pub mod utils;
