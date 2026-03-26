use clap::Parser;
use clap::Subcommand;

#[derive(Parser, Debug)]
#[command(author, version, about = "Proton Meet CLI", long_about = None)]
pub struct Args {
    #[arg(
        long,
        help = "Optional path to a TOML config file",
        default_value = "test_config.toml"
    )]
    pub config_path: Option<String>,

    #[arg(long, default_value = "https://germain.proton.black/api")]
    pub api_host: String,

    #[arg(long, default_value = "mls.germain.proton.black")]
    pub ws_host: String,

    #[arg(long, default_value = "mls.germain.proton.black")]
    pub http_host: String,

    #[arg(long)]
    pub meeting_link_name: Option<String>,

    #[arg(long)]
    pub meeting_link_password: Option<String>,

    #[arg(long, default_value_t = false, help = "Enable PSK flow for MLS join")]
    pub use_psk: bool,

    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Join a meeting with provided credentials
    Normal {},

    /// Run a predefined test scenario
    Test {
        #[arg(long, help = "Test scenario to run")]
        scenario: String,

        #[arg(long, default_value_t = 1, help = "Number of concurrent threads")]
        threads: usize,

        #[arg(long, default_value_t = 1, help = "Number of apps per thread")]
        apps_per_thread: usize,

        #[arg(long, default_value_t = false, help = "Show error details")]
        error_details: bool,

        #[arg(long, default_value_t = 0, help = "Minimum thread join delay in ms")]
        join_delay_min_ms: u64,

        #[arg(long, default_value_t = 0, help = "Maximum threadjoin delay in ms")]
        join_delay_max_ms: u64,
    },
}
