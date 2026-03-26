pub mod app_runner;
pub mod app_test_runner;
pub mod commands;
pub mod config;

use clap::Parser;

use crate::{
    app_runner::AppRunner,
    app_test_runner::AppTestRunner,
    commands::{Args, Commands},
    config::{load_test_config, AppConfig},
};

fn get_args_with_default() -> Args {
    let mut cli_args: Vec<String> = std::env::args().collect();

    // If only the binary name is given, inject default subcommand "normal"
    if cli_args.len() == 1 {
        cli_args.push("normal".to_string());
    }

    Args::parse_from(cli_args)
}

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_timer(tracing_subscriber::fmt::time::ChronoLocal::new(
            "%H:%M:%S%.3f".to_string(),
        ))
        .init();
    tracing::info!("Starting the application");

    // Parse command-line arguments
    tracing::info!("Parsing command-line arguments");
    let args = get_args_with_default();

    let config = if let Some(path) = args.config_path.clone() {
        load_test_config(&path)?
    } else {
        AppConfig {
            api_host: args.api_host.clone(),
            ws_host: args.ws_host.clone(),
            http_host: args.http_host.clone(),
            meeting_link_name: args
                .meeting_link_name
                .clone()
                .ok_or(anyhow::anyhow!("meeting_link_name is required"))?,
            meeting_link_password: args
                .meeting_link_password
                .clone()
                .ok_or(anyhow::anyhow!("meeting_link_password is required"))?,
        }
    };

    tracing::info!("Config: {:?}", config);
    match args.command {
        Commands::Normal {} => {
            let runner = AppRunner::prepare(
                config.api_host,
                config.ws_host,
                config.http_host,
                config.meeting_link_name,
                config.meeting_link_password,
                args.use_psk,
                None,
            )
            .await?;

            tracing::info!("App created and initialized");

            tracing::info!("Running logic started");

            runner.run_logic().await?;
            tracing::info!("Running logic completed");
            runner.leave().await?;
            tracing::info!("Leaving room completed");
        }
        Commands::Test {
            scenario,
            threads,
            apps_per_thread,
            error_details,
            join_delay_min_ms,
            join_delay_max_ms,
        } => {
            let mut join_delay_max_ms = join_delay_max_ms.max(join_delay_min_ms);
            tracing::info!(
                "Using join delay: min={}ms, max={}ms",
                join_delay_min_ms,
                join_delay_max_ms
            );
            if join_delay_min_ms > join_delay_max_ms {
                tracing::warn!(
                    "join_delay_max_ms is greater than join_delay_min_ms, setting join_delay_max_ms to join_delay_min_ms"
                );
                join_delay_max_ms = join_delay_min_ms;
            }

            let mut test_runner = AppTestRunner::new();
            tracing::info!("Test runner created");
            test_runner
                .run_benchmark(
                    &scenario,
                    threads,
                    apps_per_thread,
                    config,
                    args.use_psk,
                    join_delay_min_ms,
                    join_delay_max_ms,
                )
                .await?;
            test_runner.report(error_details).await;
        }
    }
    tracing::info!("Application is shutting down");

    Ok(())
}
