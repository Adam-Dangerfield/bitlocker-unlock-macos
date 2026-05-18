enable_testing()

add_executable(test_bitlocker_crypto test_crypto.c)

target_link_libraries(test_bitlocker_crypto PRIVATE bitlocker_crypto)

target_include_directories(test_bitlocker_crypto PRIVATE ${CMAKE_SOURCE_DIR}/src/bitlocker-crypto)

add_test(NAME bitlocker_crypto COMMAND test_bitlocker_crypto)
