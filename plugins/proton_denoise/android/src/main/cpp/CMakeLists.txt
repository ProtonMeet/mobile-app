cmake_minimum_required(VERSION 3.14)
project(proton_denoise LANGUAGES C CXX)

set(PROTON_DENOISE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../..")

add_library(proton_denoise SHARED
  proton_denoise_jni.cpp
)

include("${PROTON_DENOISE_ROOT}/cmake/rnnoise.cmake")
proton_denoise_configure_rnnoise_target(proton_denoise "${PROTON_DENOISE_ROOT}")

target_compile_features(proton_denoise PRIVATE cxx_std_17)

find_library(log-lib log)
target_link_libraries(proton_denoise PRIVATE ${log-lib})
