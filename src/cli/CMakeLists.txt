add_executable(bitlocker-info bitlocker_info.c)
add_executable(bitlocker-decrypt bitlocker_decrypt.c)

target_link_libraries(bitlocker-info PRIVATE bitlocker_crypto)
target_link_libraries(bitlocker-decrypt PRIVATE bitlocker_crypto)

target_include_directories(bitlocker-info PRIVATE ${CMAKE_SOURCE_DIR}/src/bitlocker-crypto)
target_include_directories(bitlocker-decrypt PRIVATE ${CMAKE_SOURCE_DIR}/src/bitlocker-crypto)

set(_cli_targets bitlocker-info bitlocker-decrypt)

# bitlocker-mount is the FUSE mount CLI — only build it when the macos_fuse
# adapter was actually built (i.e. FUSE-T / macFUSE was found). Otherwise the
# link fails with "library 'macos_fuse' not found" (e.g. on CI without FUSE).
if(TARGET macos_fuse)
    add_executable(bitlocker-mount bitlocker_mount.c)
    target_link_libraries(bitlocker-mount PRIVATE macos_fuse)
    target_include_directories(bitlocker-mount PRIVATE ${CMAKE_SOURCE_DIR}/src/macos-fuse)
    list(APPEND _cli_targets bitlocker-mount)
else()
    message(STATUS "bitlocker-mount skipped (FUSE adapter not built; FUSE not found)")
endif()

install(TARGETS ${_cli_targets} RUNTIME DESTINATION bin)
