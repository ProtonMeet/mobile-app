use std::{
    env, fs,
    path::{Path, PathBuf},
};
const RNNOISE_LIB_NAME: &str = "rnnoise";

#[cfg(any(target_os = "linux", target_os = "android"))]
const GO_LIB_SUFFIX: &str = "a";

#[cfg(target_os = "macos")]
const GO_LIB_SUFFIX: &str = "a";

#[cfg(target_os = "windows")]
const GO_LIB_SUFFIX: &str = "dll";

#[cfg(target_os = "macos")]
const MIN_MAC_OS_X_VERSION: &str = "11.0";

const MIN_IOS_VERSION: &str = "15";

#[derive(Debug, Copy, Clone, Eq, PartialEq)]
enum CPUArch {
    X86_64,
    X86,
    Aarch64,
    Arm,
}

#[derive(Debug, Copy, Clone, Eq, PartialEq)]
enum IosTarget {
    Simulator,
    SimulatorArm,
    Device,
}

#[derive(Debug, Copy, Clone, Eq, PartialEq)]
enum Platform {
    Unix(CPUArch),
    Windows(CPUArch),
    Android(CPUArch),
    Ios(IosTarget),
}

impl Platform {
    fn from_env() -> Platform {
        let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();
        let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();
        let target = env::var("TARGET").unwrap();

        if target_os == "android" {
            if target_arch == "x86_64" {
                return Platform::Android(CPUArch::X86_64);
            } else if target_arch == "aarch64" {
                return Platform::Android(CPUArch::Aarch64);
            } else if target_arch == "arm" {
                return Platform::Android(CPUArch::Arm);
            } else if target_arch == "x86" {
                return Platform::Android(CPUArch::X86);
            } else {
                panic!("unsupported android architecture: {target_arch}")
            }
        } else if target_os == "ios" {
            if target_arch == "x86_64" {
                return Platform::Ios(IosTarget::Simulator);
            }

            return if target.ends_with("-sim") {
                Platform::Ios(IosTarget::SimulatorArm)
            } else {
                Platform::Ios(IosTarget::Device)
            };
        } else if target_os == "windows" {
            return if target_arch == "x86_64" {
                Platform::Windows(CPUArch::X86_64)
            } else if target_arch == "x86" {
                Platform::Windows(CPUArch::X86)
            } else {
                panic!("unsupported architecture: {target_arch}")
            };
        }

        if target_arch == "x86_64" {
            Platform::Unix(CPUArch::X86_64)
        } else if target_arch == "aarch64" || target_arch == "arm64" {
            Platform::Unix(CPUArch::Aarch64)
        } else {
            panic!("unsupported architecture: {target_arch}")
        }
    }
}

fn main() {
    let target = env::var("TARGET").unwrap();
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();

    // Determine platform-specific static lib path
    let source_lib_dir = if target.contains("apple-darwin") {
        "rnnoise/libs/macos"
    } else if target.contains("apple-ios") {
        "rnnoise/libs/ios"
    } else if target.contains("linux") {
        "rnnoise/libs/linux"
    } else if target.contains("windows") {
        "rnnoise/libs/windows/x86_64"
    } else if target.contains("android") {
        "rnnoise/libs/android/arm64-v8a"
    } else {
        panic!("Unsupported target: {target}");
    };

    // Copy .a or .dylib to target dir
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    // Go from .../target/debug/build/<pkg>/out → target/debug or release
    let target_profile_dir = out_dir
        .ancestors()
        .nth(3)
        .expect("Unexpected OUT_DIR layout");

    let source_lib = Path::new(source_lib_dir).join("librnnoise.a");
    let dest_lib = target_profile_dir.join("librnnoise.a");
    fs::copy(&source_lib, &dest_lib).expect("Failed to copy library to output directory");
    println!("cargo:warning=Copied to {}", dest_lib.display());

    let platform = Platform::from_env();
    let (lib_dir, lib_path) = target_path_for_go_lib(platform);

    eprintln!("Warning: lib_dir: {:?}", lib_dir);
    eprintln!("Warning: lib_path: {:?}", lib_path);

    // std::fs::copy(
    //     &source_lib,
    //     lib_dir
    //         .parent()
    //         .and_then(|p| p.parent())
    //         .and_then(|p| p.parent())
    //         .expect("Failed to navigate to the correct parent directory")
    //         .join(lib_path.file_name().unwrap()),
    // )
    // .expect("Failed to copy library");

    // Tell Cargo to link the static lib
    println!(
        "cargo:rustc-link-search=native={}",
        target_profile_dir.to_str().unwrap()
    );
    println!("cargo:rustc-link-lib={RNNOISE_LIB_NAME}"); // if add =static=  .a will combined in frb

    // Generate bindings
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindgen::Builder::default()
        .header("rnnoise/include/rnnoise.h")
        .generate()
        .expect("Failed to generate bindings")
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Failed to write bindings");
}

fn target_path_for_go_lib(platform: Platform) -> (PathBuf, PathBuf) {
    let lib_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR is not empty"));
    match platform {
        Platform::Unix(_) | Platform::Windows(_) => (
            lib_dir.clone(),
            lib_dir.join(format!("lib{RNNOISE_LIB_NAME}.a")),
        ),
        Platform::Android(_) => (
            lib_dir.clone(),
            lib_dir.join(format!("lib{RNNOISE_LIB_NAME}.so")),
        ),
        Platform::Ios(_) => (
            lib_dir.clone(),
            lib_dir.join(format!("lib{RNNOISE_LIB_NAME}.a")),
        ),
    }
}
