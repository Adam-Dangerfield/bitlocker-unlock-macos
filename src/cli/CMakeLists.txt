add_executable(bitlocker-mount bitlocker_mount.c)
add_executable(bitlocker-info bitlocker_info.c)
add_executable(bitlocker-decrypt bitlocker_decrypt.c)

target_link_libraries(bitlocker-mount PRIVATE macos_fuse)
target_link_libraries(bitlocker-info PRIVATE bitlocker_crypto)
target_link_libraries(bitlocker-decrypt PRIVATE bitlocker_crypto)

target_include_directories(bitlocker-mount PRIVATE ${CMAKE_SOURCE_DIR}/src/macos-fuse)
target_include_directories(bitlocker-info PRIVATE ${CMAKE_SOURCE_DIR}/src/bitlocker-crypto)
target_include_directories(bitlocker-decrypt PRIVATE ${CMAKE_SOURCE_DIR}/src/bitlocker-crypto)

install(TARGETS bitlocker-mount bitlocker-info bitlocker-decrypt
        RUNTIME DESTINATION bin)
