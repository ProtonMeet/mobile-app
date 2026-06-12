#!/bin/sh
# Find cmake when PATH is minimal (Xcode script phases). Override: RNNOISE_CMAKE=/path/cmake

rnnoise_prepend_path() {
  for dir in \
    /opt/homebrew/bin \
    /usr/local/bin \
    /Applications/CMake.app/Contents/bin \
    "$HOME/.local/bin" \
    "$HOME/bin"
  do
    if [ -d "${dir}" ]; then
      PATH="${dir}:${PATH}"
    fi
  done

  if [ -n "${ANDROID_HOME:-}" ]; then
    _android_cmake_bin=$(
      ls -d "${ANDROID_HOME}/cmake/"*/bin 2>/dev/null | sort -V | tail -n 1
    )
    if [ -n "${_android_cmake_bin}" ] && [ -d "${_android_cmake_bin}" ]; then
      PATH="${_android_cmake_bin}:${PATH}"
    fi
  fi

  export PATH
}

rnnoise_resolve_cmake() {
  rnnoise_prepend_path

  if [ -n "${RNNOISE_CMAKE:-}" ]; then
    if [ -x "${RNNOISE_CMAKE}" ]; then
      echo "${RNNOISE_CMAKE}"
      return 0
    fi
    echo "RNNOISE_CMAKE is set but not executable: ${RNNOISE_CMAKE}" >&2
    return 1
  fi

  if [ -n "${CMAKE:-}" ] && [ -x "${CMAKE}" ]; then
    echo "${CMAKE}"
    return 0
  fi

  if command -v cmake >/dev/null 2>&1; then
    command -v cmake
    return 0
  fi

  echo "RNNoise: cmake not found (need CMake 3.14+)." >&2
  echo "  Install: brew install cmake" >&2
  echo "  Or set RNNOISE_CMAKE to the cmake binary (Xcode scheme / CI env)." >&2
  return 1
}
