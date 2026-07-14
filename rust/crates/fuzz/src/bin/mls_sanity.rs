//! Deterministic sanity probe for the stateful MLS harness.
//!
//! The fuzz harness deliberately swallows expected MLS errors, so a silently
//! *failing* operation would be indistinguishable from a passing one. This probe
//! drives a concrete, known-good sequence and prints the observable group state
//! after each step, so we can confirm join actually grows the roster, remove
//! shrinks it, and members converge — i.e. that the fuzzer is exercising real
//! group operations and not no-op'ing.
//!
//! Run: `cargo run --bin mls_sanity` (needs --cfg mls_build_async, which
//! .cargo/config.toml supplies for normal builds).
use proton_meet_fuzz::env::TestMlsEnv;

fn snapshot(env: &TestMlsEnv, label: &str) {
    let rosters: Vec<_> = env
        .active
        .iter()
        .map(|&m| (m, env.epoch_of(m), env.roster_len_of(m)))
        .collect();
    println!(
        "{label}: active={:?} (member, epoch, roster)={rosters:?}",
        env.active
    );
}

fn main() {
    let mut env = TestMlsEnv::new(3);
    println!("built {} clients", env.num_clients());

    env.create_group(0);
    snapshot(&env, "after create_group(0)      ");
    assert_eq!(
        env.active,
        vec![0],
        "create should leave exactly host active"
    );
    assert_eq!(env.roster_len_of(0), Some(1), "host roster should be 1");

    env.join(1);
    snapshot(&env, "after join(1)              ");

    env.join(2);
    snapshot(&env, "after join(2)              ");

    env.encrypt(1, b"hello world");
    env.deliver_all();
    snapshot(&env, "after encrypt(1)+deliver   ");

    env.update(0);
    env.deliver_all();
    snapshot(&env, "after update(0)+deliver    ");

    env.remove(1);
    snapshot(&env, "after remove(1)            ");

    // Verdicts.
    println!("\n--- VERDICT ---");
    println!("join grew the group:   {}", env.active.len() > 1);
    println!(
        "remove shrank the group: {}",
        !env.active.contains(&1) && !env.active.is_empty()
    );
}
