use flutter_rust_bridge::frb;
pub use proton_meet_calendar::RecurrenceFrequency;

#[frb(mirror(RecurrenceFrequency))]
pub enum _RecurrenceFrequency {
    Daily,
    Weekly,
    Monthly,
    Yearly,
}
