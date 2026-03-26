use crate::infra::http_client::ProtonHttpClient;
use muon::{common::ServiceType, ProtonRequest, DELETE, GET, POST, PUT};
use std::{env, time::Duration};

pub const DEFAULT_SERVICE_TYPE: ServiceType = ServiceType::Normal;
// get default time constraint from env, or we will use 30 as default time constraint
pub fn get_default_time_constraint() -> Duration {
    let time_constraint = env::var("DEFAULT_TIME_CONSTRAINT")
        .ok()
        .and_then(|val| val.parse::<u64>().ok())
        .unwrap_or(30); // set default time constraint to 30s

    Duration::from_secs(time_constraint)
}

pub trait HttpClientUtil {
    fn get(&self, endpoint: impl ToString) -> ProtonRequest;
    fn post(&self, endpoint: impl ToString) -> ProtonRequest;
    fn put(&self, endpoint: impl ToString) -> ProtonRequest;
    fn delete(&self, endpoint: impl ToString) -> ProtonRequest;
}

impl HttpClientUtil for ProtonHttpClient {
    fn get(&self, endpoint: impl ToString) -> ProtonRequest {
        GET!("{}", endpoint.to_string())
            .allowed_time(get_default_time_constraint())
            .service_type(DEFAULT_SERVICE_TYPE, true)
    }
    fn post(&self, endpoint: impl ToString) -> ProtonRequest {
        POST!("{}", endpoint.to_string())
            .allowed_time(get_default_time_constraint())
            .service_type(DEFAULT_SERVICE_TYPE, true)
    }
    fn put(&self, endpoint: impl ToString) -> ProtonRequest {
        PUT!("{}", endpoint.to_string())
            .allowed_time(get_default_time_constraint())
            .service_type(DEFAULT_SERVICE_TYPE, true)
    }
    fn delete(&self, endpoint: impl ToString) -> ProtonRequest {
        DELETE!("{}", endpoint.to_string())
            .allowed_time(get_default_time_constraint())
            .service_type(DEFAULT_SERVICE_TYPE, true)
    }
}
