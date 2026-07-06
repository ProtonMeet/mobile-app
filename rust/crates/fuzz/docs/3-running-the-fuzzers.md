# Running the Fuzzers

How to build, run, reproduce crashes, and measure coverage. See *Fuzzing Overview* for the concepts.

---

## One-time setup

```bash
rustup toolchain install nightly     # cargo-fuzz needs nightly
cargo install cargo-fuzz             # the `cargo fuzz` subcommand
git submodule update --init --recursive   # vendored MLS crates (needs Proton GitLab SSH)
```

---

## Running a target

Always go through **`run.sh`** — it re-injects the mandatory `--cfg mls_build_async` (which
`cargo-fuzz` otherwise drops) and sets an RSS limit:

```bash
cd rust
./crates/fuzz/run.sh <target> [seconds]     # default 60s
```

Examples:

```bash
./crates/fuzz/run.sh mimi_content 90        # a decoder — millions of execs in 90s
./crates/fuzz/run.sh mls_state_machine 300  # a stateful target — run for minutes
./crates/fuzz/run.sh mls_ratchet_tree 600
```

`run.sh` with no argument prints the target list.

**Targets:**
`mimi_content` · `chat_envelope` · `legacy_chat_json` · `message_id_hex` · `mls_message`
· `mls_state_machine` · `mls_kv_reload` · `mls_ratchet_tree` · `mls_liveness` · `mls_catchup`

> Running directly instead of via `run.sh`? Then set the cfg yourself:
> `RUSTFLAGS="--cfg mls_build_async" cargo fuzz run --fuzz-dir crates/fuzz <target> -- -max_total_time=300`

### Reading the output

libFuzzer prints periodic status lines:

```
#12345  NEW    cov: 22575 ft: 65012 corp: 231/1.4kb  exec/s: 175 ...
```

- `cov` / `ft` — coverage (edges) and features hit; rising means it's still finding new paths.
- `exec/s` — executions per second (decoders: 100k+; stateful targets: ~100–200, that's expected).
- A clean run ends with `Done N runs in T second(s)` and writes nothing to `artifacts/`.

---

## When it finds something

A crash writes a reproducing input to `crates/fuzz/artifacts/<target>/crash-<hash>` and prints the panic /
sanitizer report. Replay it:

```bash
./crates/fuzz/run.sh <target> crates/fuzz/artifacts/<target>/crash-<hash>
```

**Caveat for stateful MLS targets:** the MLS crypto uses a non-seeded system RNG, so replaying a saved
crash file may not reproduce byte-for-byte. For confirmed bugs we ship a deterministic reproduction
binary instead, e.g.:

```bash
cd rust/crates/fuzz
cargo run --bin mls_repro_361        # deterministically reproduces the #361 finding
```

To shrink a crash input before filing it:

```bash
RUSTFLAGS="--cfg mls_build_async" cargo fuzz tmin --fuzz-dir crates/fuzz <target> crates/fuzz/artifacts/<target>/crash-<hash>
```

---

## Corpus & seeds

libFuzzer keeps interesting inputs in `crates/fuzz/corpus/<target>/` and reuses them across runs (so coverage
accumulates — later runs pick up where earlier ones left off). Both `corpus/` and `artifacts/` are
git-ignored.

Seed the corpora with structurally-valid inputs (helps the parser targets reach past the outer layer):

```bash
cd rust/crates/fuzz
cargo run --bin gen_seeds            # writes real messages into corpus/<target>/
```

---

## Helper (non-fuzz) binaries

These run on the normal toolchain (no libFuzzer):

```bash
cd rust/crates/fuzz
cargo run --bin gen_seeds            # mint seed inputs
cargo run --bin mls_sanity           # sanity-check the harness: join grows the roster,
                                     # remove shrinks it, members converge (prints a summary)
cargo run --bin mls_repro_361        # deterministic reproduction of the #361 bug
```

`mls_sanity` is the quickest way to confirm the stateful harness still works after a change.

---

## Measuring coverage

```bash
cd rust
RUSTFLAGS="--cfg mls_build_async" cargo fuzz coverage --fuzz-dir crates/fuzz <target>
# then render a report with the toolchain's llvm-cov, filtered to the code you care about:
LLVMCOV="$(rustc --print sysroot)/lib/rustlib/$(rustc -vV | sed -n 's/host: //p')/bin/llvm-cov"
"$LLVMCOV" report \
  target/*/coverage/*/release/<target> \
  -instr-profile=crates/fuzz/coverage/<target>/coverage.profdata \
  $(pwd)/crates/fuzz/src $(pwd)/crates/meet-mls/src
```

Report per-directory (as above) rather than whole-graph — the full dependency graph is dominated by
large `mls-rs`/crypto crates and the number would be misleading.

---

## Building all targets (e.g. in CI)

```bash
cd rust
RUSTFLAGS="--cfg mls_build_async" cargo fuzz build --fuzz-dir crates/fuzz     # compiles every target under the sanitizer
```

**Suggested CI smoke job** (fast — catches breakage, not deep bugs):

```bash
for t in mimi_content chat_envelope legacy_chat_json message_id_hex mls_message; do
  ./crates/fuzz/run.sh "$t" 30
done
for t in mls_state_machine mls_kv_reload mls_ratchet_tree mls_liveness mls_catchup; do
  ./crates/fuzz/run.sh "$t" 60
done
```

For deeper coverage, run a nightly job for minutes-to-hours per target and persist `corpus/` between
runs. Note: `mls_ratchet_tree` currently reproduces a known unpatched `mls-rs` bug (#361), so it will
fail until the dependency is updated — exclude it from a "must be green" gate, or treat its failure as
the expected regression signal.
