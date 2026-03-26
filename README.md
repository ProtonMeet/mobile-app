# Proton Meet for mobile

Copyright (c) 2025 Proton AG

## Building

You need to install Go and Rust first:

### On macOS

```
brew install go rust android-ndk
export ANDROID_NDK_HOME="/opt/homebrew/share/android-ndk"
```

Then, in project folder:

```
git submodule init
git submodule update
```

Finally, in rust folder:

```
cargo build
```

### Build WASM file for Web

```
cd rust
cargo build --target wasm32-unknown-unknown --release
cd crates/meet-core
wasm-pack build --target web --release --out-name index
```

### Build FRB

```
brew install ndk
rustup target add x86_64-linux-android
cd rust/crates/frb
cargo ndk -t x86_64 build --release
```

## Signing

All `release` builds done on CI are automatically signed with ProtonMeet's keystore, and depending on the distribution method, they are categorized as follows:

- Google Play Store (App Bundle)
- Official APK available via our download link

## Versioning

Version matches format: `[major][minor][patch]`

## Observability

Crashes and errors that happen in `release` (non debuggable) builds are reported to Sentry in an anonymized form.

## Help us to translate the project

You can learn more about it on [our blog post](https://proton.me/blog/translation-community).

## License

The code and data files in this distribution are licensed under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See <https://www.gnu.org/licenses/> for a copy of this license.

See [LICENSE](LICENSE) file
