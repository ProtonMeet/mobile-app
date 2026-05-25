# Shared native library: TensorFlow Lite segmentation + CPU blur (Linux/Windows).
cmake_minimum_required(VERSION 3.16)

set(MEET_VIDEO_EFFECTS_NATIVE meet_video_effects_native)

set(MEET_VIDEO_EFFECTS_NATIVE_SOURCES
  src/meet_video_effects_engine.cpp
)

add_library(${MEET_VIDEO_EFFECTS_NATIVE} STATIC ${MEET_VIDEO_EFFECTS_NATIVE_SOURCES})
target_include_directories(${MEET_VIDEO_EFFECTS_NATIVE} PUBLIC include)

# TensorFlow Lite: set TFLITE_ROOT to a CMake build tree of tensorflow/lite, e.g.
#   cmake -S tensorflow/tensorflow/lite -B tflite-build -DCMAKE_BUILD_TYPE=Release
#   cmake --build tflite-build -j
# Then: -DTFLITE_ROOT=/path/to/tflite-build
set(TFLITE_ROOT "" CACHE PATH "Path to TensorFlow Lite CMake build directory")

if(TFLITE_ROOT)
  find_path(TFLITE_INCLUDE_DIR tensorflow/lite/c/c_api.h
    PATHS "${TFLITE_ROOT}" "${TFLITE_ROOT}/include" NO_DEFAULT_PATH)
  find_library(TFLITE_LIB tensorflow-lite PATHS "${TFLITE_ROOT}" NO_DEFAULT_PATH)
  if(TFLITE_INCLUDE_DIR AND TFLITE_LIB)
    target_include_directories(${MEET_VIDEO_EFFECTS_NATIVE} PRIVATE "${TFLITE_INCLUDE_DIR}")
    target_link_libraries(${MEET_VIDEO_EFFECTS_NATIVE} PUBLIC "${TFLITE_LIB}")
    target_compile_definitions(${MEET_VIDEO_EFFECTS_NATIVE} PUBLIC MEET_VIDEO_EFFECTS_USE_TFLITE)
    message(STATUS "meet_video_effects: TFLite enabled (${TFLITE_LIB})")
  else()
    message(WARNING "meet_video_effects: TFLITE_ROOT set but tensorflow-lite not found — blur disabled")
  endif()
else()
  message(STATUS "meet_video_effects: TFLITE_ROOT not set — build with -DTFLITE_ROOT=... to enable blur")
endif()

target_compile_features(${MEET_VIDEO_EFFECTS_NATIVE} PUBLIC cxx_std_17)

if(MSVC)
  target_compile_options(${MEET_VIDEO_EFFECTS_NATIVE} PRIVATE /W4)
else()
  target_compile_options(${MEET_VIDEO_EFFECTS_NATIVE} PRIVATE -Wall -Wextra)
endif()
