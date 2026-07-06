#![no_main]
//! Stateful MLS fuzzing: drive a real multi-client group through an
//! `arbitrary`-generated sequence of create / join / update / remove / encrypt /
//! deliver / drop / replay / reorder / corrupt operations, asserting cross-member
//! convergence after every step.
//!
//! Property targets: not just crashes, but *logical* MLS state bugs — silent
//! divergence between members at the same epoch, ghost members after add/remove,
//! and panics inside the client/group code on out-of-order / replayed / corrupted
//! messages (which must be handled as errors, never panics).
use libfuzzer_sys::fuzz_target;
use proton_meet_fuzz::env::TestMlsEnv;
use proton_meet_fuzz::ops::{Op, Scenario};

// Lossy/adversarial delivery (drop/reorder/replay/corrupt) means members
// legitimately fork (same epoch via different commits), so cross-member tree
// convergence is NOT asserted here — that invariant requires totally-ordered
// delivery and lives in `mls_liveness`. This target's property is "no panic in
// the MLS client/group code under hostile, out-of-order, corrupted input".
fuzz_target!(|scenario: Scenario| {
    let mut env = TestMlsEnv::new(5);
    env.create_group(0);

    for op in scenario.ops.into_iter().take(64) {
        apply(&mut env, op);
    }
});

fn apply(env: &mut TestMlsEnv, op: Op) {
    match op {
        Op::Join { joiner } => env.join(joiner),
        Op::Add { adder, addee } => env.add_member(adder, addee),
        Op::Update { member } => env.update(member),
        Op::Leave { member } => env.remove(member),
        Op::Encrypt { sender, payload } => env.encrypt(sender, &payload),
        Op::DeliverNext => env.deliver_next(),
        Op::DeliverAll => env.deliver_all(),
        Op::DropNext => env.drop_next(),
        Op::ReplayOld { msg_index } => env.replay_old(msg_index),
        Op::ReorderQueue => env.reorder_queue(),
        Op::CorruptQueued {
            msg_index,
            byte_index,
            value,
        } => env.corrupt_queued(msg_index, byte_index, value),
        Op::ReloadStore { member } => env.reload(member),
    }
}
