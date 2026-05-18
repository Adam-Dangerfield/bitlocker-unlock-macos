add_library(macos_fuse STATIC
    macos_fuse.c
)

target_include_directories(macos_fuse
    PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(macos_fuse
    PUBLIC bitlocker_crypto fuse_interface
)

target_compile_definitions(macos_fuse
    PUBLIC FUSE_USE_VERSION=31
)
