add_library(bitlocker_crypto STATIC
    bitlocker_crypto.c
)

target_include_directories(bitlocker_crypto
    PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(bitlocker_crypto
    PUBLIC OpenSSL::Crypto
)

target_compile_definitions(bitlocker_crypto
    PUBLIC BITLOCKER_CRYPTO_IMPLEMENTATION
)
