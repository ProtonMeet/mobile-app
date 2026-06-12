# Links proton_denoise to prebuilt dtln-rs static libraries (Android ABI slices).

function(proton_denoise_configure_dtln_rs_target target_name plugin_root)
  set(DTLN_RS_ROOT "${plugin_root}/third_party/dtln-rs")
  set(DTLN_RS_LIB "${DTLN_RS_ROOT}/lib/android/${ANDROID_ABI}/libdtln.a")

  if(NOT EXISTS "${DTLN_RS_LIB}")
    message(FATAL_ERROR
      "dtln-rs: missing ${DTLN_RS_LIB} — run plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh android "
      "(supported ANDROID_ABI: armeabi-v7a, arm64-v8a, x86_64; not legacy x86)")
  endif()

  target_include_directories(${target_name} PRIVATE
    "${plugin_root}/common/cpp/include"
    "${DTLN_RS_ROOT}/include"
  )

  target_sources(${target_name} PRIVATE
    "${plugin_root}/common/cpp/src/proton_dtln_c_api.cc"
  )

  target_compile_definitions(${target_name} PRIVATE PROTON_DTLN_RS_BUILD)

  target_link_libraries(${target_name} PRIVATE
    -Wl,--whole-archive
    "${DTLN_RS_LIB}"
    -Wl,--no-whole-archive
    atomic
    m
  )
endfunction()
