//! Targeted reproduction of the leaf-index-reuse sender-aliasing bug fixed by
//! awslabs/mls-rs PR #361 (the nexun fork we pin, rev 9a180d16, is unpatched).
//!
//! Scenario:
//!   1. host(0) creates the group; alice(1) and bob(2) join.
//!   2. alice encrypts an application message M (captured, not yet replayed).
//!   3. alice is removed — her leaf index is freed.
//!   4. charlie(3) joins and (per MLS leftmost-blank-leaf reuse) takes alice's
//!      old leaf index.
//!   5. We replay alice's pre-removal message M to bob and host.
//!
//! Expected (PATCHED) behavior: M must NOT be accepted as an application message
//! attributed to alice's old leaf — the signing identity at that leaf changed
//! (it's charlie now), so decryption should fail with a MemberNotFound-style
//! error. If instead M is ACCEPTED and attributed to that leaf, that is the
//! aliasing bug (#361).
//!
//! Run: `cargo run --bin mls_repro_361`.
use proton_meet_fuzz::env::{RecvKind, TestMlsEnv};

fn main() {
    let mut env = TestMlsEnv::new(4); // 0 host, 1 alice, 2 bob, 3 charlie
    env.create_group(0);
    env.join(1);
    env.join(2);

    let alice_leaf = env.leaf_u32(1);
    println!(
        "alice joined at leaf {alice_leaf:?}, roster(host)={:?}",
        env.roster_len_of(0)
    );

    // alice produces an application message at the current epoch.
    let Some(m_alice) = env.encrypt_capture(1, b"secret from alice") else {
        println!("FAILED to capture alice's message; cannot test");
        return;
    };

    // Remove alice (frees her leaf), then charlie joins and may reuse it.
    env.remove(1);
    env.join(3);
    let charlie_leaf = env.leaf_u32(3);
    let reused = alice_leaf.is_some() && alice_leaf == charlie_leaf;
    println!(
        "after remove(alice)+join(charlie): charlie leaf {charlie_leaf:?}, reused alice's leaf = {reused}"
    );

    // Replay alice's OLD message now that charlie occupies (possibly) her leaf.
    let on_bob = env.deliver_report(2, &m_alice);
    let on_host = env.deliver_report(0, &m_alice);
    println!("replay alice's pre-removal message -> bob:  {on_bob:?}");
    println!("replay alice's pre-removal message -> host: {on_host:?}");

    println!("\n--- VERDICT (#361 leaf-reuse sender aliasing) ---");
    let aliased = |k: &RecvKind| match k {
        // Accepted as an app message attributed to alice's now-reused leaf.
        RecvKind::App { sender, .. } => alice_leaf == Some(*sender),
        _ => false,
    };
    let bug = aliased(&on_bob) || aliased(&on_host);
    if bug {
        println!(
            "BUG REPRODUCED: a removed member's prior message was accepted and \
             attributed to the new occupant of her leaf index."
        );
    } else {
        println!(
            "not reproduced via this path (message rejected / not aliased). \
             reused_leaf={reused}; bob={on_bob:?}; host={on_host:?}"
        );
    }
}
