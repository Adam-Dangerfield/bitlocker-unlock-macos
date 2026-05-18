cmake_minimum_required(VERSION 3.15)
project(bitlocker_macos VERSION 0.1.0 LANGUAGES C)

# NOTE: the working unlock toolchain is built by ./build.sh, which configures
# the upstream dislocker source vendored at third_party/dislocker/. This root
# CMakeLists.txt drives the (still-stub) macOS-native rewrite under src/ — see
# README.md "Milestone 3" for the long-term plan. Both can coexist.

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(USE_OPENSSL "Use OpenSSL libcrypto"           ON)
option(USE_MBEDTLS "Use mbedTLS libcrypto"           OFF)
option(BUILD_MACOS_FUSE "Build the src/macos-fuse adapter (requires FUSE-T or macFUSE)" AUTO)

find_package(OpenSSL REQUIRED)

# ---------- FUSE-T / macFUSE detection (optional) ----------
find_path(FUSE_INCLUDE_DIR
    NAMES fuse.h fuse/fuse.h
    PATHS
        /usr/local/include
        /opt/homebrew/include
        /opt/local/include
        /Library/Frameworks/fuse-t.framework/Headers
        /Library/Frameworks/macfuse.framework/Headers
        /Library/Frameworks/osxfuse.framework/Headers
)

find_library(FUSE_LIBRARY
    NAMES fuse-t fuse fuse3
    PATHS
        /usr/local/lib
        /opt/homebrew/lib
        /opt/local/lib
        /Library/Frameworks/fuse-t.framework
        /Library/Frameworks/macfuse.framework
        /Library/Frameworks/osxfuse.framework
)

if(FUSE_INCLUDE_DIR AND FUSE_LIBRARY)
    set(HAVE_FUSE TRUE)
    message(STATUS "FUSE found: ${FUSE_LIBRARY} (headers: ${FUSE_INCLUDE_DIR})")
    add_library(fuse_interface INTERFACE)
    target_include_directories(fuse_interface INTERFACE ${FUSE_INCLUDE_DIR})
    target_link_libraries(fuse_interface INTERFACE ${FUSE_LIBRARY})
else()
    set(HAVE_FUSE FALSE)
    message(STATUS "FUSE not found — skipping src/macos-fuse target. "
                   "Install fuse-t (`brew install --cask fuse-t`) to enable.")
endif()

# ---------- subdirs ----------
add_subdirectory(src/bitlocker-crypto)
if(HAVE_FUSE AND (BUILD_MACOS_FUSE STREQUAL "AUTO" OR BUILD_MACOS_FUSE))
    add_subdirectory(src/macos-fuse)
endif()
add_subdirectory(src/cli)
add_subdirectory(tests)

install(DIRECTORY src/cli/
        DESTINATION bin
        FILES_MATCHING PATTERN "*.sh" EXCLUDE)
