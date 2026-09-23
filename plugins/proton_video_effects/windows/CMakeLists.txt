cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "proton_video_effects")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "proton_video_effects_plugin")

set(MODEL_SOURCE "${CMAKE_CURRENT_LIST_DIR}/../android/src/main/assets/selfie_segmenter.tflite")

add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../native" meet_video_effects_native_build)

list(APPEND PLUGIN_SOURCES
  "proton_video_effects_plugin.cpp"
  # Platform-agnostic; anything Windows-specific it needs is declared in
  # common/desktop and implemented by the *_win.cpp sources below.
  "../common/desktop/desktop_background_blur.cpp"
  "../common/desktop/desktop_log.cpp"
  "desktop_image_decoder_win.cpp"
  "desktop_webrtc_instance_win.cpp"
)

# The frame tap needs flutter_webrtc's headers. Both plugins are symlinked as
# siblings under windows/flutter/ephemeral/.plugin_symlinks, so this path holds
# for any Flutter build; the guard keeps the plugin building on its own (or in an
# app without flutter_webrtc), just without the tap.
set(FLUTTER_WEBRTC_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../flutter_webrtc")
if(EXISTS "${FLUTTER_WEBRTC_ROOT}/common/cpp/include/flutter_webrtc.h")
  list(APPEND PLUGIN_SOURCES
    "../common/desktop/desktop_frame_tap.cpp"
    "../common/desktop/desktop_webrtc_internals.cpp"
  )
  set(MEET_VIDEO_EFFECTS_HAS_WEBRTC ON)
  message(STATUS "meet_video_effects: frame tap enabled (${FLUTTER_WEBRTC_ROOT})")
else()
  set(MEET_VIDEO_EFFECTS_HAS_WEBRTC OFF)
  message(STATUS "meet_video_effects: flutter_webrtc not found — frame tap disabled")
endif()

add_library(${PLUGIN_NAME} SHARED
  "include/proton_video_effects/proton_video_effects_plugin_c_api.h"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../common/desktop"
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/include"
)

if(MEET_VIDEO_EFFECTS_HAS_WEBRTC)
  target_include_directories(${PLUGIN_NAME} PRIVATE
    "${FLUTTER_WEBRTC_ROOT}/common/cpp/include"
    "${FLUTTER_WEBRTC_ROOT}/third_party/libwebrtc/include"
  )
  # Must match how flutter_webrtc itself was compiled: RTC_DESKTOP_DEVICE gates
  # members of FlutterWebRTCBase, so disagreeing on it would give the two
  # libraries different ideas of the object's layout.
  target_compile_definitions(${PLUGIN_NAME} PRIVATE
    RTC_DESKTOP_DEVICE
    LIB_WEBRTC_API_DLL
    MEET_VIDEO_EFFECTS_HAS_WEBRTC
  )
  # flutter_webrtc's plugin library is deliberately not linked — its shared
  # instance is resolved with GetProcAddress and every call into it is virtual.
  # libwebrtc does have to be linked, because portable::string's destructor is
  # out-of-line, and RTCMediaTrack::kind() returns one by value. The DLL is
  # already bundled by flutter_webrtc, so this adds no new runtime artefact.
  target_link_libraries(${PLUGIN_NAME} PRIVATE
    "${FLUTTER_WEBRTC_ROOT}/third_party/libwebrtc/lib/libwebrtc.dll.lib")
endif()

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)
target_link_libraries(${PLUGIN_NAME} PRIVATE meet_video_effects_native)
# WIC decodes the replacement background image (desktop_image_decoder_win.cpp).
target_link_libraries(${PLUGIN_NAME} PRIVATE windowscodecs ole32)

if(EXISTS "${MODEL_SOURCE}")
  add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${MODEL_SOURCE}"
      "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/selfie_segmenter.tflite"
    COMMENT "Copy selfie_segmenter.tflite next to ${PLUGIN_NAME}"
  )
  # The copy above only serves the build tree. The plugin resolves the model
  # relative to its own loaded module, which is the installed copy in the
  # bundle, so the model has to be installed alongside it as well.
  set(MODEL_BUNDLED "${MODEL_SOURCE}")
else()
  set(MODEL_BUNDLED "")
endif()

set(proton_video_effects_bundled_libraries
  "${MODEL_BUNDLED}"
  # tensorflowlite_c.dll when TFLite is built as the shared C library.
  "${MEET_VIDEO_EFFECTS_RUNTIME_LIB}"
  PARENT_SCOPE
)
