# Shared native library: TensorFlow Lite segmentation + CPU blur (Linux/Windows).
cmake_minimum_required(VERSION 3.16)

# Normally pulled in via add_subdirectory from linux/ or windows/, but also
# configurable on its own so the engine tests can be built and run without a
# full Flutter build.
if(CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
  project(meet_video_effects_native LANGUAGES CXX)
  option(MEET_VIDEO_EFFECTS_BUILD_TESTS "Build the engine tests" ON)
else()
  option(MEET_VIDEO_EFFECTS_BUILD_TESTS "Build the engine tests" OFF)
endif()

set(MEET_VIDEO_EFFECTS_NATIVE meet_video_effects_native)

set(MEET_VIDEO_EFFECTS_NATIVE_SOURCES
  src/meet_video_effects_engine.cpp
  src/meet_video_effects_custom_ops.cpp
)

add_library(${MEET_VIDEO_EFFECTS_NATIVE} STATIC ${MEET_VIDEO_EFFECTS_NATIVE_SOURCES})
target_include_directories(${MEET_VIDEO_EFFECTS_NATIVE} PUBLIC include)

# === TensorFlow Lite ===
# Resolved in this order:
#   1. TFLITE_ROOT, from the CMake cache or the environment: a TFLite build tree
#      or staged dist, for anyone who builds the runtime themselves.
#   2. The prebuilt runtime vendored in third_party/tflite, which is what a
#      plain `flutter build` uses so that nobody has to compile TensorFlow.
# tools/build_tflite.ps1 / build_tflite.sh reproduce (2) from source.
set(TFLITE_ROOT "" CACHE PATH
  "TensorFlow Lite build or staged dist; overrides the vendored prebuilt")

# `flutter build windows/linux` forwards no user-supplied CMake arguments, so an
# environment variable is the only way to point at a TFLite build when the build
# is driven by the Flutter CLI rather than CMake directly.
if(NOT TFLITE_ROOT AND DEFINED ENV{TFLITE_ROOT})
  set(TFLITE_ROOT "$ENV{TFLITE_ROOT}")
  message(STATUS "meet_video_effects: TFLITE_ROOT from environment (${TFLITE_ROOT})")
endif()

# Prebuilt binaries are specific to a platform and architecture, so they live in
# per-ABI directories and are only ever used for the ABI being built. An
# unrecognised target leaves this empty and falls through to "blur disabled"
# rather than linking some other platform's library.
if(CMAKE_SIZEOF_VOID_P EQUAL 8 AND NOT CMAKE_SYSTEM_PROCESSOR MATCHES "[Aa][Rr][Mm]|aarch64")
  if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set(TFLITE_ABI "windows-x64")
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(TFLITE_ABI "linux-x64")
  endif()
endif()

set(TFLITE_VENDORED_ROOT "${CMAKE_CURRENT_LIST_DIR}/third_party/tflite")
if(NOT TFLITE_ROOT AND TFLITE_ABI
   AND EXISTS "${TFLITE_VENDORED_ROOT}/lib/${TFLITE_ABI}")
  set(TFLITE_ROOT "${TFLITE_VENDORED_ROOT}")
  message(STATUS "meet_video_effects: using vendored TFLite prebuilt (${TFLITE_ABI})")
endif()

if(TFLITE_ROOT)
  find_path(TFLITE_INCLUDE_DIR tensorflow/lite/c/c_api.h
    PATHS "${TFLITE_ROOT}" "${TFLITE_ROOT}/include" NO_DEFAULT_PATH)
  # The per-ABI directory comes first so the vendored prebuilt is matched before
  # any generic layout. The rest cover a self-built tree: multi-config
  # generators (Visual Studio) put the library under a per-config subdirectory,
  # single-config ones leave it at the top of the build tree.
  set(TFLITE_SEARCH_PATHS
    "${TFLITE_ROOT}/lib/${TFLITE_ABI}"
    "${TFLITE_ROOT}"
    "${TFLITE_ROOT}/lib"
    "${TFLITE_ROOT}/Release"
    "${TFLITE_ROOT}/Debug"
    "${TFLITE_ROOT}/RelWithDebInfo")
  find_library(TFLITE_LIB
    NAMES tensorflowlite_c tensorflow-lite
    PATHS ${TFLITE_SEARCH_PATHS}
    NO_DEFAULT_PATH)

  # The shared build needs its runtime library shipped next to the plugin; the
  # static one links everything in and has nothing to copy.
  find_file(TFLITE_RUNTIME_LIB
    NAMES tensorflowlite_c.dll libtensorflowlite_c.so libtensorflowlite_c.dylib
    PATHS ${TFLITE_SEARCH_PATHS}
    NO_DEFAULT_PATH)

  if(TFLITE_INCLUDE_DIR AND TFLITE_LIB)
    target_include_directories(${MEET_VIDEO_EFFECTS_NATIVE} PRIVATE "${TFLITE_INCLUDE_DIR}")
    target_link_libraries(${MEET_VIDEO_EFFECTS_NATIVE} PUBLIC "${TFLITE_LIB}")
    target_compile_definitions(${MEET_VIDEO_EFFECTS_NATIVE} PUBLIC MEET_VIDEO_EFFECTS_USE_TFLITE)
    message(STATUS "meet_video_effects: TFLite enabled (${TFLITE_LIB})")
    if(TFLITE_RUNTIME_LIB)
      message(STATUS "meet_video_effects: TFLite runtime to bundle (${TFLITE_RUNTIME_LIB})")
    endif()
  else()
    message(WARNING
      "meet_video_effects: no TFLite C library for ${TFLITE_ABI} under ${TFLITE_ROOT} "
      "— blur disabled. Build one with native/tools/build_tflite.ps1|sh. "
      "See native/third_party/tflite/README.md.")
  endif()
else()
  # Reached when the target ABI has no vendored prebuilt (for example Linux
  # before libtensorflowlite_c.so has been built, or an arm64 host).
  message(WARNING
    "meet_video_effects: no TFLite runtime for this target — blur disabled. "
    "Build one with native/tools/build_tflite.ps1|sh and drop it in "
    "native/third_party/tflite/lib/<abi>/, or set TFLITE_ROOT. See native/README.md.")
endif()

# Consumed by the linux/ and windows/ plugin CMake to add the runtime library to
# the Flutter bundle. Empty for a static TFLite or when TFLite is disabled.
if(NOT CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
  set(MEET_VIDEO_EFFECTS_RUNTIME_LIB "${TFLITE_RUNTIME_LIB}" PARENT_SCOPE)
endif()

target_compile_features(${MEET_VIDEO_EFFECTS_NATIVE} PUBLIC cxx_std_17)

if(MSVC)
  target_compile_options(${MEET_VIDEO_EFFECTS_NATIVE} PRIVATE /W4)
else()
  target_compile_options(${MEET_VIDEO_EFFECTS_NATIVE} PRIVATE -Wall -Wextra)
endif()

# === Tests ===
# Engine tests run real inference, so they need TFLite and the model. The
# platform CMake sets include_proton_video_effects_tests when building the
# example, matching how proton_denoise gates its tests.
if((include_proton_video_effects_tests OR MEET_VIDEO_EFFECTS_BUILD_TESTS)
   AND TFLITE_INCLUDE_DIR AND TFLITE_LIB)
  set(MEET_VIDEO_EFFECTS_TEST_MODEL
    "${CMAKE_CURRENT_LIST_DIR}/../android/src/main/assets/selfie_segmenter.tflite")
  if(NOT EXISTS "${MEET_VIDEO_EFFECTS_TEST_MODEL}")
    message(WARNING "meet_video_effects: segmentation model missing — engine tests skipped")
  else()
    enable_testing()
    include(FetchContent)
    FetchContent_Declare(googletest
      URL https://github.com/google/googletest/archive/release-1.11.0.zip)
    set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
    set(INSTALL_GTEST OFF CACHE BOOL "Disable installation of googletest" FORCE)
    FetchContent_MakeAvailable(googletest)

    add_executable(meet_video_effects_native_test test/meet_video_effects_engine_test.cpp)
    target_link_libraries(meet_video_effects_native_test
      PRIVATE ${MEET_VIDEO_EFFECTS_NATIVE} gtest_main)
    target_compile_definitions(meet_video_effects_native_test PRIVATE
      "MEET_VIDEO_EFFECTS_TEST_MODEL_PATH=\"${MEET_VIDEO_EFFECTS_TEST_MODEL}\"")
    if(TFLITE_RUNTIME_LIB)
      # The engine resolves TFLite at load time, so the runtime has to sit next
      # to the test binary just as it does next to the app.
      add_custom_command(TARGET meet_video_effects_native_test POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "${TFLITE_RUNTIME_LIB}" $<TARGET_FILE_DIR:meet_video_effects_native_test>)
    endif()

    include(GoogleTest)
    gtest_discover_tests(meet_video_effects_native_test)
  endif()
endif()
