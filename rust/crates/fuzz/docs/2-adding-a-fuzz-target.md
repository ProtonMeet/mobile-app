# Adding a Fuzz Target

A step-by-step guide for developers. Read *Fuzzing Overview* first if you haven't.

There are two kinds of target. Pick based on what you're testing:

- **A decoder** — you have a function that parses untrusted bytes/strings. → Section A (easy, ~15 min).
- **A stateful behaviour** — you want to check an MLS group invariant. → Section B (reuses the harness).

Every target follows the same three mechanical steps, then you write the important part — the **oracle**.

---

## Section A — a decoder target

### 1. Write the target file

Create `crates/fuzz/fuzz_targets/my_thing.rs`:

```rust
#![no_main]
//! Fuzz `my_crate::parse_thing` — <where the bytes come from and why it's untrusted>.
use libfuzzer_sys::fuzz_target;
use my_crate::parse_thing;

fuzz_target!(|data: &[u8]| {
    // Oracle 1: must never panic on arbitrary input.
    let Ok(parsed) = parse_thing(data) else { return; };

    // Oracle 2 (optional but valuable): decode->encode->decode round-trips.
    let reencoded = parsed.to_bytes();
    let reparsed = parse_thing(&reencoded).expect("re-parsing our own output must succeed");
    assert_eq!(parsed, reparsed, "round-trip changed the value");
});
```

Prefer `let Ok(x) = ... else { return }` over `.unwrap()` — a parse *error* is expected and fine; a
*panic* is the bug.

### 2. Register it in `crates/fuzz/Cargo.toml`

Add the crate you're testing to `[dependencies]` if it isn't there, then add a `[[bin]]`:

```toml
[[bin]]
name = "my_thing"
path = "fuzz_targets/my_thing.rs"
test = false
doc = false
bench = false
```

### 3. Build & smoke-test

```bash
cd rust
./crates/fuzz/run.sh my_thing 30      # 30-second smoke run
```

That's it. See *Running the Fuzzers* for seeding a corpus and longer runs.

---

## Section B — a stateful MLS target

These reuse the shared harness in `src/env.rs` (`TestMlsEnv`) and the operation model in `src/ops.rs`.
You usually don't touch `env.rs` unless you need a new invariant.

### 1. Write the target file

Create `crates/fuzz/fuzz_targets/my_mls_check.rs`. Drive `TestMlsEnv` with the fuzzed `Scenario`, then assert
your invariant:

```rust
#![no_main]
use libfuzzer_sys::fuzz_target;
use proton_meet_fuzz::env::TestMlsEnv;
use proton_meet_fuzz::ops::{Op, Scenario};

fuzz_target!(|scenario: Scenario| {
    let mut env = TestMlsEnv::new(5);   // 5 real MLS clients
    env.create_group(0);

    for op in scenario.ops.into_iter().take(64) {
        match op {
            Op::Join { joiner }        => env.join(joiner),
            Op::Add { adder, addee }   => env.add_member(adder, addee),
            Op::Update { member }      => env.update(member),
            Op::Leave { member }       => env.remove(member),
            Op::Encrypt { sender, payload } => env.encrypt(sender, &payload),
            Op::DeliverAll             => env.deliver_all(),
            _ => {}                     // handle only the ops your check needs
        }
        // your invariant here, e.g.:
        // env.check_sender_integrity();
    }
});
```

Register it in `Cargo.toml` exactly as in Section A step 2, then `./crates/fuzz/run.sh my_mls_check 120`.

### 2. Reuse an existing oracle, or add one

`env.rs` already exposes reusable checks:

| Method | Asserts |
|---|---|
| `check_sender_integrity()` | removed member's message not re-attributed to a reused leaf |
| `assert_all_converged()` | all active members share epoch + roster + full tree |
| `reload(member)` | save→reload preserves that member's state |
| `catchup()` | an offline member re-syncs by replaying commits in order |
| `tree_bytes_of(m)` / `epoch_of(m)` / `roster_len_of(m)` | building blocks for your own checks |

To add a new invariant, add a `pub fn` on `TestMlsEnv` in `env.rs` that inspects the members and
`assert!`s the property, then call it from your target.

---

## Writing a *good* oracle (the part that matters)

1. **No-panic is the floor, not the goal.** Any target catches panics for free. Add a real property.
2. **Round-trip / idempotency** is a cheap, strong oracle for anything with encode+decode.
3. **For stateful checks, assert only where the precondition holds.** Real example from this repo: the
   invariant "members at the same epoch have the same tree" is only valid under **lossless, in-order
   delivery**. Asserting it in a target that drops/reorders messages produced *false positives*,
   because MLS legitimately "forks" (two members commit concurrently → same epoch number, different
   trees) — that fork is resolved by the server in production, not by the library. So convergence is
   asserted only in `mls_liveness`/`mls_catchup` (which deliver in order), never in the lossy targets.
   **Before you assert an invariant, ask: could a *correct* implementation break this under the
   delivery model my target uses?**
4. **Keep inputs bounded** so runs stay fast and reproducible: cap op counts (`.take(64)`), payload
   sizes, and client counts.

---

## Checklist

- [ ] `fuzz_targets/<name>.rs` with `#![no_main]` + `fuzz_target!` and a **documented oracle**.
- [ ] `[[bin]]` entry in `crates/fuzz/Cargo.toml` (+ any new `[dependencies]`).
- [ ] `./crates/fuzz/run.sh <name> 30` builds and runs clean.
- [ ] (optional) seed inputs added to `gen_seeds` or dropped into `corpus/<name>/`.
- [ ] For a reproducible bug: a deterministic `src/bin/<name>_repro.rs` (crypto RNG isn't seeded, so
      saved crash files may not replay).
