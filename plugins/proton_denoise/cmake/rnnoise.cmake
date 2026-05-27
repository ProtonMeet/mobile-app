# Links proton_denoise native code to a CMake-built RNNoise static library.
#
# Expects:
#   plugin_root — proton_denoise root directory

function(proton_denoise_configure_rnnoise_target target_name plugin_root)
  if(APPLE AND RNNOISE_OSX_DEPLOYMENT_TARGET)
    # Set by parent (e.g. linux host build) or empty on Apple pods (built separately).
  elseif(APPLE)
    set(RNNOISE_OSX_DEPLOYMENT_TARGET "12.0")
  endif()

  include("${plugin_root}/cmake/rnnoise_upstream.cmake")

  target_include_directories(${target_name} PRIVATE
    "${plugin_root}/common/cpp/include"
    "${RNNOISE_INCLUDE_DIR}"
  )

  target_sources(${target_name} PRIVATE
    "${plugin_root}/common/cpp/src/proton_rnnoise_processor.cc"
    "${plugin_root}/common/cpp/src/proton_rnnoise_c_api.cc"
  )

  target_compile_definitions(${target_name} PRIVATE PROTON_RNNOISE_BUILD)

  target_link_libraries(${target_name} PRIVATE rnnoise::rnnoise)
endfunction()
