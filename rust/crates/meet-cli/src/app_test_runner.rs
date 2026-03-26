use std::{collections::HashMap, sync::Arc};

use rand::Rng;
use tokio::{sync::Mutex, time::Instant};

use crate::{app_runner::AppRunner, config::AppConfig};

pub struct AppTestRunner {
    pub metrics: Arc<tokio::sync::Mutex<HashMap<String, String>>>,
    pub error_counts: Arc<tokio::sync::Mutex<HashMap<String, usize>>>,
    pub error_messages: Arc<tokio::sync::Mutex<HashMap<String, String>>>,
}

impl AppTestRunner {
    pub fn new() -> Self {
        Self {
            metrics: Arc::new(Mutex::new(HashMap::new())),
            error_counts: Arc::new(Mutex::new(HashMap::new())),
            error_messages: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn run_benchmark(
        &mut self,
        scenario: &str,
        threads: usize,
        apps_per_thread: usize,
        config: AppConfig,
        use_psk: bool,
        join_delay_min_ms: u64,
        join_delay_max_ms: u64,
    ) -> Result<(), anyhow::Error> {
        {
            let mut metrics = self.metrics.lock().await;
            metrics.insert(
                "total_clients".into(),
                format!("{} clients", threads * apps_per_thread),
            );
            metrics.insert("threads_number".into(), format!("{threads}"));
            metrics.insert("apps_per_thread".into(), format!("{apps_per_thread}"));
        }
        match scenario {
            "join" => {
                let start = Instant::now();
                let mut thread_handles = vec![];
                for t in 0..threads {
                    let api = config.api_host.clone();
                    let ws = config.ws_host.clone();
                    let name = config.meeting_link_name.clone();
                    let pwd = config.meeting_link_password.clone();
                    let http_host = config.http_host.clone();

                    let error_counts = self.error_counts.clone();
                    let error_messages = self.error_messages.clone();
                    let handle = tokio::spawn(async move {
                        let mut handles: Vec<tokio::task::JoinHandle<()>> = vec![];
                        for i in 0..apps_per_thread {
                            let tag = format!("thread{t}_app{i}");
                            let api = api.clone();
                            let ws = ws.clone();
                            let http = http_host.clone();
                            let name = name.clone();
                            let pwd = pwd.clone();
                            let error_counts = error_counts.clone();
                            let error_messages = error_messages.clone();
                            let h = tokio::spawn(async move {
                                // Simulate staggered join
                                if join_delay_max_ms > 0 {
                                    let delay_ms = if join_delay_max_ms == join_delay_min_ms {
                                        join_delay_min_ms
                                    } else {
                                        rand::thread_rng()
                                            .gen_range(join_delay_min_ms..join_delay_max_ms)
                                    };
                                    tracing::info!(
                                        "Thread {} app {} joined after {}ms",
                                        t,
                                        i,
                                        delay_ms
                                    );
                                    tokio::time::sleep(std::time::Duration::from_millis(delay_ms))
                                        .await;
                                }
                                match AppRunner::prepare(
                                    api,
                                    ws,
                                    http,
                                    name.clone(),
                                    pwd.clone(),
                                    use_psk,
                                    Some(tag.clone()),
                                )
                                .await
                                {
                                    Ok(runner) => {
                                        let _ = runner.run_logic().await;

                                        let _ = runner.leave().await;
                                    }
                                    Err(e) => {
                                        let error_msg =
                                            format!("[{tag}] Failed to prepare app: {e}");
                                        tracing::error!("{}", error_msg.clone());
                                        let mut error_messages = error_messages.lock().await;
                                        *error_messages.entry(tag.clone()).or_default() = error_msg;

                                        let mut errors = error_counts.lock().await;
                                        *errors.entry(tag.clone()).or_default() += 1;
                                    }
                                }
                            });
                            handles.push(h);
                        }
                        for h in handles {
                            let _ = h.await;
                        }
                    });
                    thread_handles.push(handle);
                }

                for h in thread_handles {
                    let _ = h.await;
                }
                let mut metrics = self.metrics.lock().await;
                metrics.insert(
                    "total_duration_ms".into(),
                    format!("{} ms", start.elapsed().as_millis()),
                );
            }
            _ => {
                println!("Unknown test scenario: {scenario}");
            }
        }
        Ok(())
    }

    pub async fn report(&self, with_details: bool) {
        println!("Test Results:");
        let metrics = self.metrics.lock().await;
        for (k, v) in metrics.iter() {
            println!("  {k}: {v}");
        }

        println!("Errors - Total: {:?}", self.error_counts.lock().await.len());

        if with_details {
            println!("Error messages:");
            let error_messages = self.error_messages.lock().await;
            for (tag, msg) in error_messages.iter() {
                println!("  {tag}: {msg}");
            }
        }
    }
}

impl Default for AppTestRunner {
    fn default() -> Self {
        Self::new()
    }
}
