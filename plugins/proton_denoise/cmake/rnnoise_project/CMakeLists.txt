# Standalone RNNoise build invoked by scripts/rnnoise/build_rnnoise.sh (Apple) and tests.
cmake_minimum_required(VERSION 3.14)
project(rnnoise_build C)

if(NOT RNNOISE_OSX_DEPLOYMENT_TARGET)
  if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(RNNOISE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "")
  else()
    set(RNNOISE_OSX_DEPLOYMENT_TARGET "12.0" CACHE STRING "")
  endif()
endif()

include(../rnnoise_upstream.cmake)
