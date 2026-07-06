#![no_main]
//! Catch-up correctness fuzzing — the sound vehicle for the mls-rs #352 bug class
//! (spurious `ParentHashMismatch` on a blank ancestor whose descendant's
//! `unmerged_leaves` changed).
//!
//! `mls_liveness` delivers every commit immediately and everyone merges, so
//! unmerged leaves never persist long enough to coexist with a blank ancestor —
//! it structurally cannot reach the #352 shape. This target instead takes one
//! member **offline** (its commits are withheld into a canonical-order backlog)
//! while the rest of the group churns via add / remove / update, then brings it
//! back and replays the withheld commits **in order**.
//!
//! Oracle (`env.catchup`): applying the canonical commit sequence in order must
//! never fail — a rejection of a legitimate catch-up commit is a spurious
//! validation failure (#352 class), and after catch-up the member must converge
//! with its peers. This is sound (single canonical chain ⇒ no fork) and models a
//! real reconnecting client.
use libfuzzer_sys::fuzz_target;
use proton_meet_fuzz::env::TestMlsEnv;
use proton_meet_fuzz::ops::{Op, Scenario};

fuzz_target!(|scenario: Scenario| {
    let mut env = TestMlsEnv::new(8);
    env.create_group(0);
    // Seed a few members so there is a tree to churn and someone to take offline.
    env.add_member(0, 1);
    env.add_member(0, 2);
    env.add_member(1, 3);

    // Take member 3 offline; its commits accumulate in the backlog.
    if env.set_excluded(3).is_none() {
        return;
    }

    // Churn the group (adds create unmerged leaves; removes blank ancestors).
    for op in scenario.ops.into_iter().take(80) {
        match op {
            Op::Add { adder, addee } => env.add_member(adder, addee),
            Op::Update { member } => env.update(member),
            Op::Leave { member } => env.remove(member),
            Op::Join { joiner } => env.join(joiner),
            Op::DeliverAll => env.deliver_all(),
            Op::DeliverNext => env.deliver_next(),
            _ => {}
        }
    }
    // Flush any queued commits (update commits) to online members + the backlog.
    env.deliver_all();

    // Bring the offline member back and replay the canonical sequence in order.
    env.catchup();
});
