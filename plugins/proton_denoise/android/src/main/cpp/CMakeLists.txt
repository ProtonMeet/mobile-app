cmake_minimum_required(VERSION 3.14)
project(proton_denoise LANGUAGES C CXX)

set(PROTON_DENOISE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../..")

add_library(proton_denoise SHARED
  proton_denoise_jni.cpp
  "${PROTON_DENOISE_ROOT}/common/cpp/src/proton_deepfilter_dlopen.cc"
)

target_include_directories(proton_denoise PRIVATE
  "${PROTON_DENOISE_ROOT}/common/cpp/include"
  "${PROTON_DENOISE_ROOT}/third_party/deepfilter/include"
)

include("${PROTON_DENOISE_ROOT}/cmake/rnnoise.cmake")
proton_denoise_configure_rnnoise_target(proton_denoise "${PROTON_DENOISE_ROOT}")

include("${PROTON_DENOISE_ROOT}/cmake/dtln_rs.cmake")
proton_denoise_configure_dtln_rs_target(proton_denoise "${PROTON_DENOISE_ROOT}")

target_compile_features(proton_denoise PRIVATE cxx_std_17)

find_library(log-lib log)
find_library(dl-lib dl)
target_link_libraries(proton_denoise PRIVATE ${log-lib} ${dl-lib})
