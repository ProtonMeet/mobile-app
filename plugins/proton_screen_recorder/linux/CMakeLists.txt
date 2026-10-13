cmake_minimum_required(VERSION 3.14)
project(proton_screen_recorder LANGUAGES CXX)

set(PLUGIN_NAME "proton_screen_recorder_plugin")

add_library(${PLUGIN_NAME} SHARED
  "proton_screen_recorder_plugin.cc"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

set(proton_screen_recorder_bundled_libraries
  ""
  PARENT_SCOPE
)
