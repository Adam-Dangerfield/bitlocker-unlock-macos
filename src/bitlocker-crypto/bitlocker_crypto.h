#ifndef BITLOCKER_CRYPTO_H
#define BITLOCKER_CRYPTO_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BITLOCKER_AES_BLOCK_SIZE 16

typedef enum {
    BITLOCKER_ALGO_AES_CBC,
    BITLOCKER_ALGO_AES_XTS,
} bitlocker_algo_t;

bool bitlocker_crypto_init(void);
int bitlocker_decrypt_volume_header(const uint8_t *encrypted, size_t length, uint8_t *output);
int bitlocker_decrypt_sector(const uint8_t *ciphertext, uint8_t *plaintext,
                             size_t length, const uint8_t *key, const uint8_t *iv,
                             bitlocker_algo_t algo);
int bitlocker_derive_key(const uint8_t *password, size_t password_len,
                         const uint8_t *salt, size_t salt_len,
                         uint8_t *derived_key, size_t key_len);
int bitlocker_apply_elephant_diffuser(uint8_t *data, size_t length);

#ifdef __cplusplus
}
#endif

#endif // BITLOCKER_CRYPTO_H
