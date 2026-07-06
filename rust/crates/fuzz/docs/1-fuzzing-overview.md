# Fuzzing the Rust Core — Overview

This page explains **what fuzzing we run on the Rust core, how it is organized, and the ideas behind
it**. If you just want to run it, see *Running the Fuzzers*. If you want to add a new target, see
*Adding a Fuzz Target*.

---

## What is fuzzing (in one paragraph)

A fuzzer feeds a function huge numbers of automatically-generated inputs and watches for a property
to break. libFuzzer is **coverage-guided**: it mutates inputs and keeps the ones that reach new code,
so it explores deep paths on its own. We use it (via `cargo-fuzz`, with AddressSanitizer) on the parts
of the Rust core that handle **data we don't control** — bytes from the server, from other group
members, or across the Flutter↔Rust bridge.

The key idea: a fuzzer only finds a bug if you tell it **what "broken" means**. That check is called
the **oracle**. The weakest oracle is "it must not crash". Stronger oracles assert real invariants
(e.g. "two group members at the same epoch must have the same tree"). Most of the value is in the
oracle, not in the raw fuzzing.

---

## Two kinds of targets

### 1. Input decoders — "never panic on hostile bytes"

These wrap a single parser that runs on untrusted input and assert it never panics (and, where it
makes sense, that decode→encode round-trips). Examples:

| Target | What it decodes |
|---|---|
| `mimi_content` | CBOR chat message + the decode-to-event pipeline |
| `chat_envelope` | the legacy JSON-vs-binary chat envelope |
| `legacy_chat_json` | legacy JSON chat message (the FRB `parse_chat_message` path) |
| `message_id_hex` | 64-char hex message id |
| `mls_message` | TLS-encoded MLS message (Welcome / GroupInfo / Commit / Proposal) |

They are cheap (millions of executions per minute) and are the first thing to add for any new parser.

### 2. Stateful MLS harness — "the group logic stays correct"

MLS group operations (create / join / add / remove / leave) are **stateful and behind a crypto wall**
— you can't just throw random bytes at them. Instead the harness spins up several **real, initialized
MLS clients in one process** and drives them through random *sequences* of operations, then checks
invariants after each step. Targets:

| Target | Invariant it checks (its "oracle") |
|---|---|
| `mls_state_machine` | no panic under any op / (mis)delivered message |
| `mls_ratchet_tree` | a removed member's old message is never accepted as a new member (no sender spoofing) |
| `mls_kv_reload` | saving a group and reloading it reproduces the exact same state |
| `mls_liveness` | under lossless delivery, all members converge on the same epoch + tree |
| `mls_catchup` | a member that goes offline and replays commits in order re-syncs correctly |

These are slow (~100–200 exec/s — real crypto + an async runtime per step) but reach deep into the
TreeKEM client/group code. They found a real bug (see *Fuzz Testing Report*).

---

## Repository layout

```
rust/crates/fuzz/
├── Cargo.toml           # the cargo-fuzz crate: deps + one [[bin]] per target
├── run.sh               # helper to build/run a target (handles the cfg below)
├── fuzz_targets/        # one file per fuzz target (the libFuzzer entry points)
│   ├── mimi_content.rs
│   ├── mls_state_machine.rs
│   └── ...
├── src/
│   ├── lib.rs           # shared harness library (exposed as `proton_meet_fuzz`)
│   ├── env.rs           # TestMlsEnv: builds real MLS clients, drives ops, holds the oracles
│   ├── ops.rs           # the `arbitrary`-derived operation model libFuzzer mutates
│   └── bin/             # plain (non-fuzz) helper binaries
│       ├── gen_seeds.rs     # mints valid seed inputs for the corpora
│       ├── mls_sanity.rs    # deterministic check that the harness ops really work
│       └── mls_repro_361.rs # deterministic reproduction of a found bug
├── corpus/    (git-ignored)  # accumulated interesting inputs, per target
└── artifacts/ (git-ignored)  # crash-reproducing inputs, per target
```

Stateful targets share `src/env.rs` + `src/ops.rs`; decoders are standalone.

---

## Two repo-specific things to know

1. **`--cfg mls_build_async` is mandatory.** The vendored MLS crates only compile with this cfg. It is
   set in `rust/.cargo/config.toml`, but `cargo-fuzz` overrides `RUSTFLAGS` (for the sanitizer) and
   *drops* it. **`run.sh` re-injects it** — always build/run through `run.sh`, or set
   `RUSTFLAGS="--cfg mls_build_async"` yourself.

2. **The fuzz crate is a workspace member but excluded from `default-members`.** It must be a member
   so it inherits the pinned `Cargo.lock` and the `ciborium` patch, but a plain `cargo build` would
   fail to link it (no libFuzzer runtime). So `cargo build` at the repo root ignores it, and the
   fuzzers are built only via `cargo fuzz` / `run.sh`.

---

## What the harness deliberately does *not* do

- It builds MLS clients from the **light** vendored crates only (`mls-trait`, `mls-types`, `identity`,
  `proton-claims`, `proton-meet-mls`) — **not** `meet-core` (which would drag in OpenSSL/SQLite/muon).
- The MLS **protocol crypto** (signatures, tree/parent hashes, key schedule) is `mls-rs`'s
  responsibility; we fuzz how our code *parses, drives, and validates around* it, not the crypto math.
- Crash reproduction for the stateful targets is best-effort: the crypto uses a non-seeded RNG, so a
  saved crash file may not replay byte-for-byte. Deterministic bugs get a dedicated `mls_repro_*`
  binary instead.
