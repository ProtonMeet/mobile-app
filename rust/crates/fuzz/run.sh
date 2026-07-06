#!/usr/bin/env bash
# Helper to run the proton-meet-app fuzz targets.
#
# IMPORTANT: cargo-fuzz sets its own RUSTFLAGS (sanitizer + coverage), which
# REPLACES the `--cfg mls_build_async` configured in ../../.cargo/config.toml
# ([build] rustflags). Without that cfg, the vendored mls / mimi crates fail to
# compile. cargo does NOT merge the RUSTFLAGS env var with [build] rustflags from
# config, so we must re-inject the cfg here; cargo-fuzz appends its own flags to
# whatever RUSTFLAGS we provide.
set -euo pipefail

export RUSTFLAGS="--cfg mls_build_async ${RUSTFLAGS:-}"

# The fuzz project lives at tests/fuzz (not the cargo-fuzz default of ./fuzz),
# so tell cargo-fuzz where to find it. Resolve it from this script's location so
# run.sh works from any cwd.
FUZZ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET="${1:-}"
DURATION="${2:-60}"

if [[ -z "$TARGET" ]]; then
  echo "usage: $0 <target> [seconds]"
  echo "decode targets:    mimi_content chat_envelope legacy_chat_json message_id_hex mls_message"
  echo "stateful targets:  mls_state_machine mls_kv_reload mls_ratchet_tree mls_liveness mls_catchup"
  exit 1
fi

exec cargo fuzz run --fuzz-dir "$FUZZ_DIR" "$TARGET" -- -max_total_time="$DURATION" -rss_limit_mb=4096
