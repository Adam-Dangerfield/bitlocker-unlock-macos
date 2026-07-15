add_library(macos_fuse STATIC
    macos_fuse.c
)

target_include_directories(macos_fuse
    PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(macos_fuse
    PUBLIC bitlocker_crypto fuse_interface
)

# fuse-t / macFUSE expose the FUSE 2.x API; match it (the handlers in
# macos_fuse.c use the 2.x getattr/readdir/fill_dir signatures).
# _FILE_OFFSET_BITS=64 is required by fuse_common.h.
target_compile_definitions(macos_fuse
    PUBLIC FUSE_USE_VERSION=26 _FILE_OFFSET_BITS=64
)
