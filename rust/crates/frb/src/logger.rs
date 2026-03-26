use chrono::Local;
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use std::{
    env,
    fs::{File, OpenOptions},
    io::{self, Write},
    path::Path,
    sync::{Arc, Mutex},
};
use tracing::{error, info};
use tracing_appender::non_blocking::WorkerGuard;
use tracing_subscriber::{fmt::time::ChronoLocal, fmt::MakeWriter, layer::SubscriberExt};

use crate::{errors::BridgeError, flutter_logger::FlutterLogLayer};

lazy_static! {
    static ref LOG_GUARD: Mutex<Option<WorkerGuard>> = Mutex::new(None);
}

#[frb(sync)]
pub fn init_rust_logging(
    file_path: &str,
    file_name: &str,
    flutter_layer: bool,
) -> Result<(), BridgeError> {
    // Set the RUST_LOG environment variable
    env::set_var("RUST_LOG", "debug");
    info!("Initializing Rust logging with file: {}", file_path);

    // Acquire the lock on LOG_GUARD
    let guard_check = LOG_GUARD.lock()?;
    // Check if LOG_GUARD contains Some(WorkerGuard)
    if (guard_check.is_some()) {
        return Err(BridgeError::MutexLock(
            "Logger is already locked".to_string(),
        ));
    }
    drop(guard_check);

    // Create a rotating file writer
    let rotating_writer = RotatingFileWriter::new(file_path, file_name);
    let (file_writer, guard) = tracing_appender::non_blocking(rotating_writer);

    // Create a layer for logging to file
    let file_layer = tracing_subscriber::fmt::layer()
        .with_writer(file_writer)
        .with_ansi(false) // Disable ANSI colors in file logs
        .with_level(true)
        .with_timer(ChronoLocal::new("%H:%M:%S%.3f".to_string()));

    // Create a layer for logging to console
    let console_layer = tracing_subscriber::fmt::layer()
        .with_writer(std::io::stdout) // Console output
        .with_ansi(true) // Enable ANSI colors for console readability
        .with_level(true)
        .with_timer(ChronoLocal::new("%H:%M:%S%.3f".to_string()));

    let subscriber = tracing_subscriber::registry()
        .with(file_layer)
        .with(console_layer)
        // bool::then() returns Option<T>, which Layer is implemented for
        .with(flutter_layer.then(|| FlutterLogLayer::new()));

    // Set the combined subscriber as the global default
    tracing::subscriber::set_global_default(subscriber).map_err(|e| {
        BridgeError::TracingsSubscriber(format!("Failed to set global subscriber: {}", e))
    })?;

    // Keep the guard alive to ensure file logs are flushed
    *LOG_GUARD.lock()? = Some(guard);

    info!("Initializing Rust logging with file: {}", file_path);

    Ok(())
}

// File size limit in bytes (50 MB)
const MAX_LOG_SIZE: u64 = 10 * 1024 * 1024;

pub struct RotatingFileWriter {
    file: Arc<Mutex<File>>,
    file_folder: String,
    file_path: String,
}

impl RotatingFileWriter {
    pub fn new(file_folder: &str, file_name: &str) -> Self {
        let file_path = format!("{file_folder}/{file_name}");
        let file = Arc::new(Mutex::new(
            Self::open_log_file(&file_path)
                .unwrap_or_else(|err| panic!("Failed to open initial log file: {err:?}")),
        ));
        Self {
            file,
            file_folder: file_folder.to_string(),
            file_path,
        }
    }

    pub(crate) fn open_log_file(file_path: &str) -> io::Result<File> {
        OpenOptions::new()
            .create(true)
            .truncate(false)
            .append(true)
            .open(file_path)
    }

    pub(crate) fn check_file_size(&self) -> bool {
        // Check if file exists first to avoid unnecessary error logging
        if !Path::new(&self.file_path).exists() {
            // File doesn't exist - this can happen after rotation or if file was deleted
            // Return false to skip rotation check, the file will be recreated on next write
            return false;
        }

        match std::fs::metadata(&self.file_path) {
            Ok(metadata) => metadata.len() >= MAX_LOG_SIZE,
            Err(e) => {
                // Only log unexpected errors (not NotFound, as we already checked above)
                if e.kind() != io::ErrorKind::NotFound {
                    error!("Unable to read file metadata: {:?}", e);
                }
                false
            }
        }
    }

    pub(crate) fn rotate_log_file(&self) -> Result<(), io::Error> {
        // Generate a rotated file name with a timestamp
        let rotated_file_path = self.generate_rotated_file_name();
        info!("Rotating log file to: {}", rotated_file_path);

        // Attempt to rename the file and handle errors
        std::fs::rename(&self.file_path, &rotated_file_path)?;

        // Open a new log file with the original name and handle errors
        match Self::open_log_file(&self.file_path) {
            Ok(new_file) => {
                let mut file_lock = self
                    .file
                    .lock()
                    .map_err(|e| io::Error::other(format!("Failed to lock file: {e}")))?;
                *file_lock = new_file;
            }
            Err(e) => {
                info!("Failed to open new log file after rotation: {:?}", e);
            }
        }

        Ok(())
    }

    pub(crate) fn generate_rotated_file_name(&self) -> String {
        let timestamp = Local::now().format("%Y%m%d%H%M%S").to_string();
        let extension = Path::new(&self.file_path)
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("");
        let base_name = Path::new(&self.file_path)
            .file_stem()
            .and_then(|stem| stem.to_str())
            .unwrap_or("log");
        if extension.is_empty() {
            format!("{}/{}_{}.log", self.file_folder, base_name, timestamp)
        } else {
            format!(
                "{}/{}_{}.{}",
                self.file_folder, base_name, timestamp, extension
            )
        }
    }
}

impl Write for RotatingFileWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let mut file = self
            .file
            .lock()
            .map_err(|e| io::Error::other(format!("Failed to lock file: {e}")))?;

        // Try to write, and if it fails because file doesn't exist, recreate it
        let bytes_written = match file.write(buf) {
            Ok(n) => {
                // Write succeeded - release lock before checking file size
                drop(file);
                n
            }
            Err(e)
                if e.kind() == io::ErrorKind::NotFound || e.kind() == io::ErrorKind::BrokenPipe =>
            {
                // File was deleted or handle is stale - recreate it
                drop(file);
                let new_file = Self::open_log_file(&self.file_path)?;
                let mut file_lock = self
                    .file
                    .lock()
                    .map_err(|e| io::Error::other(format!("Failed to lock file: {e}")))?;
                *file_lock = new_file;
                let written = file_lock.write(buf)?;
                drop(file_lock);
                written
            }
            Err(e) => return Err(e),
        };

        let check = self.check_file_size();
        if check {
            info!("Start rotate_log_file");
            self.rotate_log_file()?;
        }
        Ok(bytes_written)
    }

    fn flush(&mut self) -> io::Result<()> {
        let mut file = self
            .file
            .lock()
            .map_err(|e| io::Error::other(format!("Failed to lock file: {e}")))?;
        file.flush()
    }
}

impl<'a> MakeWriter<'a> for RotatingFileWriter {
    type Writer = RotatingFileWriter;

    fn make_writer(&'a self) -> Self::Writer {
        RotatingFileWriter {
            file: Arc::clone(&self.file),
            file_path: self.file_path.clone(),
            file_folder: self.file_folder.clone(),
        }
    }
}
