#![no_main]
//! Liveness / agreement fuzzing — targets the mls-rs #352 parent-hash validation
//! bug (`different_unmerged` short-circuits on a blank ancestor whose descendant's
//! `unmerged_leaves` changed, causing a legitimate commit/join to fail with
//! `ParentHashMismatch`).
//!
//! Unlike `mls_state_machine`/`mls_ratchet_tree`, this target uses **reliable
//! broadcast with no message loss**: it applies only group-membership operations
//! (join / update / remove), delivers every produced commit to all members, and
//! asserts **full convergence** after each step. Under correct MLS, all members
//! must agree on epoch + roster + tree shape; if one falls behind, it rejected a
//! legitimate commit — exactly the #352 failure mode. (Drop/reorder/corrupt ops
//! are intentionally excluded here so that any divergence is a real rejection
//! bug, not expected message loss.)
use libfuzzer_sys::fuzz_target;
use proton_meet_fuzz::env::TestMlsEnv;
use proton_meet_fuzz::ops::{Op, Scenario};

fuzz_target!(|scenario: Scenario| {
    let mut env = TestMlsEnv::new(8); // larger groups → deeper trees → more chance of the #352 shape
    env.create_group(0);

    for op in scenario.ops.into_iter().take(80) {
        match op {
            Op::Join { joiner } => env.join(joiner),
            Op::Add { adder, addee } => env.add_member(adder, addee),
            Op::Update { member } => env.update(member),
            Op::Leave { member } => env.remove(member),
            // Only membership-changing ops; no lossy delivery in this target.
            _ => continue,
        }
        // Reliable broadcast: flush every queued commit to all members, then
        // require universal agreement.
        env.deliver_all();
        env.assert_all_converged();
    }
});
