//! Tokio-backed OS hooks for muon's native hyper connector.

use std::pin::Pin;
use std::time::Duration;

use futures::Future;
use muon::rt::{
    InstantFactory, Monotonic, MuonInstant, MuonSystemTime, OperatingSystem, Resolve,
    SinceUnixEpoch, Sleep, SystemTimeFactory, TcpConnect,
};

/// Spawns muon futures onto the host tokio runtime.
#[derive(Debug, Clone)]
pub struct TokioExecutor;

impl futures::task::Spawn for TokioExecutor {
    fn spawn_obj(
        &self,
        future: futures::task::FutureObj<'static, ()>,
    ) -> Result<(), futures::task::SpawnError> {
        let _ = tokio::spawn(future);
        Ok(())
    }
}

#[derive(Debug, Clone)]
pub struct MeetOs {
    time: TokioTime,
    dialer: TokioDialer,
    resolver: TokioResolver,
}

impl Default for MeetOs {
    fn default() -> Self {
        Self {
            time: TokioTime {
                at_start: std::time::Instant::now(),
            },
            dialer: TokioDialer,
            resolver: TokioResolver,
        }
    }
}

#[derive(Debug, Clone)]
pub struct TokioTime {
    at_start: std::time::Instant,
}

impl Sleep for TokioTime {
    type Sleep<'a>
        = Pin<Box<dyn Future<Output = ()> + Send + Sync + 'a>>
    where
        Self: 'a;

    fn sleep(&self, duration: Duration) -> Self::Sleep<'static> {
        Box::pin(tokio::time::sleep(duration))
    }
}

impl InstantFactory for TokioTime {
    type Instant = MuonInstant;

    fn now(&self) -> Self::Instant {
        MuonInstant::from_duration(std::time::Instant::now() - self.at_start)
    }
}

unsafe impl Monotonic for TokioTime {}

impl SystemTimeFactory for TokioTime {
    type SystemTime = MuonSystemTime;

    fn now(&self) -> Self::SystemTime {
        let elapsed = match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
            Ok(duration) => duration,
            Err(_) => Duration::ZERO,
        };
        MuonSystemTime::since_unix_epoch(elapsed)
    }
}

#[derive(Debug, Clone, Default)]
pub struct TokioDialer;

impl TcpConnect for TokioDialer {
    type Socket = async_compat::Compat<tokio::net::TcpStream>;

    async fn tcp_connect(&self, addr: std::net::SocketAddr) -> Result<Self::Socket, Self::Err> {
        tokio::net::TcpStream::connect(addr)
            .await
            .map(async_compat::Compat::new)
    }

    type Err = std::io::Error;
}

#[derive(Debug, Clone, Default)]
pub struct TokioResolver;

impl Resolve for TokioResolver {
    async fn resolve(&self, host: &str) -> muon::Result<Vec<std::net::IpAddr>, Self::Err> {
        let addr = tokio::net::lookup_host(format!("{host}:0")).await?;
        Ok(addr.map(|addr| addr.ip()).collect())
    }

    type Err = std::io::Error;
}

impl OperatingSystem for MeetOs {
    type Resolver = TokioResolver;
    type TcpConnector = TokioDialer;
    type Time = TokioTime;

    fn get_time_capabilities(&self) -> &Self::Time {
        &self.time
    }

    fn get_tcp_connector(&self) -> &Self::TcpConnector {
        &self.dialer
    }

    fn get_resolver(&self) -> &Self::Resolver {
        &self.resolver
    }
}
