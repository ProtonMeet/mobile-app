cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "proton_video_effects")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "proton_video_effects_plugin")

set(MODEL_SOURCE "${CMAKE_CURRENT_LIST_DIR}/../android/src/main/assets/selfie_segmenter.tflite")

add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../native" meet_video_effects_native_build)

list(APPEND PLUGIN_SOURCES
  "proton_video_effects_plugin.cpp"
  "../common/desktop/desktop_background_blur.cpp"
)

add_library(${PLUGIN_NAME} SHARED ${PLUGIN_SOURCES})

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../common/desktop"
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)
target_link_libraries(${PLUGIN_NAME} PRIVATE meet_video_effects_native)

if(EXISTS "${MODEL_SOURCE}")
  add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${MODEL_SOURCE}"
      "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/selfie_segmenter.tflite"
    COMMENT "Copy selfie_segmenter.tflite next to ${PLUGIN_NAME}"
  )
endif()

set(proton_video_effects_bundled_libraries
  ""
  PARENT_SCOPE
)
