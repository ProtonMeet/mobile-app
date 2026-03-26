use crate::frb_generated::StreamSink;
use crossbeam_channel::{unbounded, Receiver, Sender};
use flutter_rust_bridge::frb;
use once_cell::sync::OnceCell;
use std::{panic, thread};

static SENDER: OnceCell<Sender<String>> = OnceCell::new();

#[frb(sync)]
pub fn initialize_panic_hook(stream_sink: StreamSink<String>) {
    // Create a channel once and spawn a forwarder that owns the StreamSink
    let (tx, rx): (Sender<String>, Receiver<String>) = unbounded();
    if SENDER.set(tx).is_err() {
        // already initialized
        return;
    }

    // Forwarder: runs on its own thread and is the ONLY place that uses stream_sink
    thread::spawn(move || {
        for msg in rx.iter() {
            // never unwrap in a panic path
            let _ = stream_sink.add(msg);
        }
    });

    // Install the hook
    panic::set_hook(Box::new(|info| {
        let payload = info
            .payload()
            .downcast_ref::<&str>()
            .map(|s| (*s).to_owned())
            .or_else(|| info.payload().downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "Unknown panic".to_string());

        let location = info
            .location()
            .map(|loc| format!("{}:{}:{}", loc.file(), loc.line(), loc.column()))
            .unwrap_or_else(|| "Unknown location".to_string());

        let msg = format!("Panic occurred: {}\nLocation: {}", payload, location);
        // also write to stderr just in case
        eprintln!("{}", &msg);
        if let Some(tx) = SENDER.get() {
            // non-blocking best-effort send
            let _ = tx.send(msg);
        }
    }));
}
