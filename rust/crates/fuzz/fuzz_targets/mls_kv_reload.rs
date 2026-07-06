#![no_main]
//! Persistence / reload fuzzing for the meet-mls `MemKv` store.
//!
//! Drives the same MLS operation model as `mls_state_machine`, but persists each
//! active member's group to its kv and reloads it from storage at two
//! checkpoints (mid-scenario and end). The reload asserts the group's epoch and
//! roster are unchanged across a `write_to_storage` → `load_group` round-trip —
//! catching persistence bugs such as "reload resurrects a removed member",
//! "reload loses an epoch", or a panic/serde failure decoding a stored group.
use libfuzzer_sys::fuzz_target;
use proton_meet_fuzz::env::TestMlsEnv;
use proton_meet_fuzz::ops::{Op, Scenario};

// The sound oracle here is `env.reload`'s **per-member** invariant: persisting a
// group to its kv and reloading it must yield an identical (epoch, roster, full
// ratchet tree). Cross-member convergence is NOT asserted — lossy delivery lets
// members fork (that's `mls_liveness`'s domain).
fuzz_target!(|scenario: Scenario| {
    let mut env = TestMlsEnv::new(5);
    env.create_group(0);

    let ops: Vec<Op> = scenario.ops.into_iter().take(48).collect();
    let mid = ops.len() / 2;

    for op in ops[..mid].iter().cloned() {
        apply(&mut env, op);
    }
    reload_active(&mut env);

    for op in ops[mid..].iter().cloned() {
        apply(&mut env, op);
    }
    reload_active(&mut env);
});

fn reload_active(env: &mut TestMlsEnv) {
    for m in env.active.clone() {
        env.reload(m as u8);
    }
}

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
