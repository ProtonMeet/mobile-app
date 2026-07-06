#![no_main]
//! Phase 2 — ratchet-tree-focused stateful MLS fuzzing.
//!
//! Same operation model as `mls_state_machine`, but after every step it runs the
//! full set of ratchet-tree security oracles:
//!   * `check_convergence`      — active members at the same epoch agree on roster
//!                                (no ghost members / silent divergence).
//!   * `check_sender_integrity` — a removed member's prior application message must
//!                                not be accepted and attributed to whoever later
//!                                reuses the freed leaf index (mls-rs PR #361).
//!
//! NOTE: the pinned `mls-rs` fork (nexun rev 9a180d16) is **unpatched** for #361,
//! so this target is expected to find that aliasing bug once libFuzzer evolves a
//! remove → leaf-reuse → replay sequence (reproduced deterministically by
//! `cargo run --bin mls_repro_361`). After the dependency is patched, this target
//! becomes a clean regression guard.
use libfuzzer_sys::fuzz_target;
use proton_meet_fuzz::env::TestMlsEnv;
use proton_meet_fuzz::ops::{Op, Scenario};

// Lossy delivery ⇒ forks are legitimate, so cross-member convergence is not
// asserted here (see `mls_liveness` for that). The sound oracle for this target
// is `check_sender_integrity`: a removed member's message must never be accepted
// and attributed to the new occupant of its reused leaf (mls-rs #361) — a
// per-message property unaffected by forks.
fuzz_target!(|scenario: Scenario| {
    let mut env = TestMlsEnv::new(5);
    env.create_group(0);

    for op in scenario.ops.into_iter().take(96) {
        apply(&mut env, op);
        env.check_sender_integrity();
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
