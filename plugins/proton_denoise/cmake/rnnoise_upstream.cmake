# Fetches xiph/rnnoise and builds static target `rnnoise` (no prebuilt third_party libs).
#
# Optional cache variables:
#   RNNOISE_GIT_TAG — default v0.2
#   RNNOISE_OSX_DEPLOYMENT_TARGET — macOS/iOS minimum (from parent or 12.0)

cmake_minimum_required(VERSION 3.14)

include(FetchContent)

if(NOT DEFINED RNNOISE_GIT_TAG)
  set(RNNOISE_GIT_TAG "v0.2")
endif()

# Committed offline cache: plugins/plugin-cache/downloads/rnnoise/{rnnoise-*.tar.gz,rnnoise_data-*.tar.gz}
set(_rnnoise_plugin_cache_downloads
  "${CMAKE_CURRENT_LIST_DIR}/../../plugin-cache/downloads/rnnoise")
set(_rnnoise_source_archive
  "${_rnnoise_plugin_cache_downloads}/rnnoise-${RNNOISE_GIT_TAG}.tar.gz")
set(_rnnoise_fetch_src "${CMAKE_BINARY_DIR}/_deps/rnnoise_upstream-src")

set(FETCHCONTENT_QUIET OFF)
FetchContent_Declare(
  rnnoise_upstream
  GIT_REPOSITORY https://github.com/xiph/rnnoise.git
  GIT_TAG ${RNNOISE_GIT_TAG}
  GIT_SHALLOW TRUE
)

if(EXISTS "${_rnnoise_source_archive}")
  if(NOT EXISTS "${_rnnoise_fetch_src}/include/rnnoise.h")
    file(MAKE_DIRECTORY "${_rnnoise_fetch_src}")
    message(STATUS "RNNoise: extracting cached source archive ${_rnnoise_source_archive}")
    execute_process(
      COMMAND ${CMAKE_COMMAND} -E tar xzf "${_rnnoise_source_archive}"
      WORKING_DIRECTORY "${_rnnoise_fetch_src}"
      RESULT_VARIABLE _rnnoise_src_extract_result
      OUTPUT_VARIABLE _rnnoise_src_extract_out
      ERROR_VARIABLE _rnnoise_src_extract_err
    )
    if(NOT _rnnoise_src_extract_result EQUAL 0 OR NOT EXISTS "${_rnnoise_fetch_src}/include/rnnoise.h")
      message(FATAL_ERROR
        "RNNoise source extract failed (code ${_rnnoise_src_extract_result}):\n${_rnnoise_src_extract_out}\n${_rnnoise_src_extract_err}")
    endif()
  endif()
  set(FETCHCONTENT_SOURCE_DIR_RNNOISE_UPSTREAM "${_rnnoise_fetch_src}")
  set(FETCHCONTENT_UPDATES_DISCONNECTED_RNNOISE_UPSTREAM ON)
  message(STATUS "RNNoise: using cached source archive ${_rnnoise_source_archive}")
else()
  # Legacy unpacked cache (prefetch migrates this to rnnoise-<tag>.tar.gz).
  set(_rnnoise_legacy_src
    "${CMAKE_CURRENT_LIST_DIR}/../../plugin-cache/rnnoise/${RNNOISE_GIT_TAG}/source")
  if(EXISTS "${_rnnoise_legacy_src}/include/rnnoise.h")
    set(FETCHCONTENT_SOURCE_DIR_RNNOISE_UPSTREAM "${_rnnoise_legacy_src}")
    set(FETCHCONTENT_UPDATES_DISCONNECTED_RNNOISE_UPSTREAM ON)
    message(STATUS "RNNoise: using legacy unpacked source at ${_rnnoise_legacy_src}")
  endif()
endif()

FetchContent_MakeAvailable(rnnoise_upstream)

set(_rnnoise_src_dir "${rnnoise_upstream_SOURCE_DIR}")
set(_rnnoise_data_c "${_rnnoise_src_dir}/src/rnnoise_data.c")

if(NOT EXISTS "${_rnnoise_data_c}")
  find_program(_RN_CURL curl)
  find_program(_RN_WGET wget)
  if(NOT _RN_CURL AND NOT _RN_WGET)
    message(FATAL_ERROR
      "rnnoise_data.c missing and neither curl nor wget is available to download models")
  endif()

  file(READ "${_rnnoise_src_dir}/model_version" _rnnoise_model_version)
  string(STRIP "${_rnnoise_model_version}" _rnnoise_model_version)
  set(_rnnoise_model_tar "rnnoise_data-${_rnnoise_model_version}.tar.gz")
  set(_rnnoise_model_path "${_rnnoise_src_dir}/${_rnnoise_model_tar}")
  set(_rnnoise_model_url "https://media.xiph.org/rnnoise/models/${_rnnoise_model_tar}")

  if(NOT EXISTS "${_rnnoise_model_path}")
    if(NOT DEFINED _rnnoise_plugin_cache_downloads)
      set(_rnnoise_plugin_cache_downloads
        "${CMAKE_CURRENT_LIST_DIR}/../../plugin-cache/downloads/rnnoise")
    endif()
    set(_rnnoise_downloads_cache "${_rnnoise_plugin_cache_downloads}")
    if(EXISTS "${_rnnoise_downloads_cache}/${_rnnoise_model_tar}")
      set(_rnnoise_cached_model "${_rnnoise_downloads_cache}/${_rnnoise_model_tar}")
    else()
      file(GLOB _rnnoise_cached_models "${_rnnoise_downloads_cache}/rnnoise_data-*.tar.gz")
      list(LENGTH _rnnoise_cached_models _rnnoise_cached_model_count)
      if(_rnnoise_cached_model_count GREATER 0)
        list(GET _rnnoise_cached_models 0 _rnnoise_cached_model)
      endif()
    endif()
    if(DEFINED _rnnoise_cached_model AND EXISTS "${_rnnoise_cached_model}")
      message(STATUS "RNNoise: using cached model weights ${_rnnoise_cached_model}")
      file(COPY "${_rnnoise_cached_model}" DESTINATION "${_rnnoise_src_dir}")
      get_filename_component(_rnnoise_model_tar "${_rnnoise_cached_model}" NAME)
      set(_rnnoise_model_path "${_rnnoise_src_dir}/${_rnnoise_model_tar}")
    endif()
  endif()

  if(NOT EXISTS "${_rnnoise_model_path}")
    message(STATUS "Downloading RNNoise model weights into ${_rnnoise_src_dir}")
    if(_RN_WGET)
      execute_process(
        COMMAND "${_RN_WGET}" "${_rnnoise_model_url}"
        WORKING_DIRECTORY "${_rnnoise_src_dir}"
        RESULT_VARIABLE _rnnoise_dl_result
        OUTPUT_VARIABLE _rnnoise_dl_out
        ERROR_VARIABLE _rnnoise_dl_err
      )
    else()
      execute_process(
        COMMAND "${_RN_CURL}" -fL -o "${_rnnoise_model_tar}" "${_rnnoise_model_url}"
        WORKING_DIRECTORY "${_rnnoise_src_dir}"
        RESULT_VARIABLE _rnnoise_dl_result
        OUTPUT_VARIABLE _rnnoise_dl_out
        ERROR_VARIABLE _rnnoise_dl_err
      )
    endif()
    if(NOT _rnnoise_dl_result EQUAL 0 OR NOT EXISTS "${_rnnoise_model_path}")
      message(FATAL_ERROR
        "RNNoise model download failed (code ${_rnnoise_dl_result}):\n${_rnnoise_dl_out}\n${_rnnoise_dl_err}")
    endif()
  endif()

  execute_process(
    COMMAND tar xvomf "${_rnnoise_model_tar}"
    WORKING_DIRECTORY "${_rnnoise_src_dir}"
    RESULT_VARIABLE _rnnoise_tar_result
    OUTPUT_VARIABLE _rnnoise_tar_out
    ERROR_VARIABLE _rnnoise_tar_err
  )
  if(NOT _rnnoise_tar_result EQUAL 0 OR NOT EXISTS "${_rnnoise_data_c}")
    message(FATAL_ERROR
      "RNNoise model extract failed (code ${_rnnoise_tar_result}):\n${_rnnoise_tar_out}\n${_rnnoise_tar_err}")
  endif()
endif()

set(_rnnoise_lib_sources
  "${_rnnoise_src_dir}/src/denoise.c"
  "${_rnnoise_src_dir}/src/rnn.c"
  "${_rnnoise_src_dir}/src/pitch.c"
  "${_rnnoise_src_dir}/src/kiss_fft.c"
  "${_rnnoise_src_dir}/src/celt_lpc.c"
  "${_rnnoise_src_dir}/src/nnet.c"
  "${_rnnoise_src_dir}/src/nnet_default.c"
  "${_rnnoise_src_dir}/src/parse_lpcnet_weights.c"
  "${_rnnoise_src_dir}/src/rnnoise_data.c"
  "${_rnnoise_src_dir}/src/rnnoise_tables.c"
)

add_library(rnnoise STATIC ${_rnnoise_lib_sources})
add_library(rnnoise::rnnoise ALIAS rnnoise)

set(_rnnoise_shim_dir "${CMAKE_CURRENT_LIST_DIR}/shims")

target_include_directories(rnnoise
  PUBLIC
    "${_rnnoise_src_dir}/include"
  PRIVATE
    "${_rnnoise_shim_dir}"
    "${_rnnoise_src_dir}/src"
)

target_compile_definitions(rnnoise PRIVATE OPUS_BUILD=1)

if(MSVC)
  target_compile_options(rnnoise PRIVATE /W3 /O2)
else()
  target_compile_options(rnnoise PRIVATE -Wall -Wno-unused-parameter -O3 -fvisibility=hidden)
  target_link_libraries(rnnoise PRIVATE m)
endif()

# Use CMAKE_OSX_DEPLOYMENT_TARGET / OSX_DEPLOYMENT_TARGET only. Do not pass
# -mmacosx-version-min manually — it conflicts with -mios*-version-min on iOS.
if(APPLE AND RNNOISE_OSX_DEPLOYMENT_TARGET)
  set_target_properties(rnnoise PROPERTIES
    OSX_DEPLOYMENT_TARGET "${RNNOISE_OSX_DEPLOYMENT_TARGET}"
  )
endif()

if(ANDROID)
  target_compile_options(rnnoise PRIVATE -fPIC)
endif()

if(UNIX AND NOT APPLE AND NOT ANDROID)
  target_compile_options(rnnoise PRIVATE -fPIC)
endif()

set(RNNOISE_INCLUDE_DIR "${_rnnoise_src_dir}/include" CACHE INTERNAL "")
set(RNNOISE_LIBRARY rnnoise CACHE INTERNAL "")
