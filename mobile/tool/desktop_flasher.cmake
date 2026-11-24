set(MESHGRAM_FLASHER_SCRIPT "${CMAKE_CURRENT_LIST_DIR}/bundle_esptool.py")

function(meshgram_bundle_esptool platform)
  find_package(Python3 REQUIRED COMPONENTS Interpreter)
  set(helper_dir "${CMAKE_CURRENT_BINARY_DIR}/meshgram-flasher")
  add_custom_target(meshgram_esptool
    COMMAND "${Python3_EXECUTABLE}" "${MESHGRAM_FLASHER_SCRIPT}" "${helper_dir}" "${platform}"
    VERBATIM)
  add_dependencies(${BINARY_NAME} meshgram_esptool)
  install(DIRECTORY "${helper_dir}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}"
    USE_SOURCE_PERMISSIONS COMPONENT Runtime)
endfunction()
