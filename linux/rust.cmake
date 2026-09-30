# Legacy Corrosion integration — not included from linux/CMakeLists.txt.
#
# The app loads libproton_meet_frb.so from rust_builder (Cargokit). Including this
# file duplicated cargo work: Corrosion imported the workspace while Cargokit also
# built proton_meet_frb, causing many back-to-back `cargo build` runs (including
# default-members and fuzz targets).
#
# To use Corrosion manually (e.g. experiments), add `include(./rust.cmake)` back
# and remove rust_builder from pubspec — not supported for production builds.

include(FetchContent)

if(DEFINED CACHE{Rust_TOOLCHAIN} AND "${Rust_TOOLCHAIN}" STREQUAL "")
  unset(Rust_TOOLCHAIN CACHE)
endif()

FetchContent_Declare(
    Corrosion
    GIT_REPOSITORY https://github.com/corrosion-rs/corrosion.git
    GIT_TAG v0.5.1
)
FetchContent_MakeAvailable(Corrosion)

corrosion_import_crate(MANIFEST_PATH ../rust/crates/frb/Cargo.toml)

set(CRATE_NAME "proton_meet_frb")
target_link_libraries(${BINARY_NAME} PUBLIC ${CRATE_NAME})
