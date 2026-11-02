#include "bitlocker_crypto.h"
#include <openssl/evp.h>
#include <openssl/err.h>
#include <string.h>

bool bitlocker_crypto_init(void)
{
    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();
    return true;
}

static int aes_decrypt(const uint8_t *ciphertext, uint8_t *plaintext,
                       size_t length, const uint8_t *key, const uint8_t *iv,
                       const EVP_CIPHER *cipher)
{
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        return -1;
    }

    int outlen = 0;
    int tmplen = 0;

    if (!EVP_DecryptInit_ex(ctx, cipher, NULL, key, iv)) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    /* BitLocker encrypts raw sector data with no PKCS#7 padding. OpenSSL's CBC
     * path enforces padding by default, which makes DecryptFinal reject valid
     * sector-aligned ciphertext. Disable padding so we operate on the raw
     * block-aligned buffer the caller supplied. */
    EVP_CIPHER_CTX_set_padding(ctx, 0);

    if (!EVP_DecryptUpdate(ctx, plaintext, &outlen, ciphertext, (int)length)) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    if (!EVP_DecryptFinal_ex(ctx, plaintext + outlen, &tmplen)) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    EVP_CIPHER_CTX_free(ctx);
    return outlen + tmplen;
}

/* NOTE: the functions below are not yet implemented for the native rewrite.
 * They return an explicit not-implemented error (nonzero) rather than 0 so a
 * caller cannot mistake a silent no-op for success. Wire these up as part of
 * Milestone 3 (see README). */

int bitlocker_decrypt_volume_header(const uint8_t *encrypted, size_t length, uint8_t *output)
{
    (void)encrypted;
    (void)length;
    (void)output;
    return -1; /* TODO(milestone-3): not implemented */
}

int bitlocker_derive_key(const uint8_t *password, size_t password_len,
                         const uint8_t *salt, size_t salt_len,
                         uint8_t *derived_key, size_t key_len)
{
    (void)password;
    (void)password_len;
    (void)salt;
    (void)salt_len;
    (void)derived_key;
    (void)key_len;
    return -1; /* TODO(milestone-3): not implemented */
}

int bitlocker_apply_elephant_diffuser(uint8_t *data, size_t length)
{
    (void)data;
    (void)length;
    return -1; /* TODO(milestone-3): not implemented */
}

int bitlocker_decrypt_sector(const uint8_t *ciphertext, uint8_t *plaintext,
                             size_t length, const uint8_t *key, const uint8_t *iv,
                             bitlocker_algo_t algo)
{
    const EVP_CIPHER *cipher = NULL;

    switch (algo) {
        case BITLOCKER_ALGO_AES_CBC:
            cipher = EVP_aes_128_cbc();
            break;
        case BITLOCKER_ALGO_AES_XTS:
            /* TODO(milestone-3): AES-XTS is not yet supported. EVP_aes_128_xts
             * requires a 32-byte key (two 16-byte keys), but this API carries
             * no key-length argument, so initialising the XTS cipher here would
             * read past a caller-supplied 16-byte key buffer (out-of-bounds
             * read). Refuse the XTS path until the key length is plumbed
             * through, rather than risk the OOB read. */
            return -1;
        default:
            return -1;
    }

    return aes_decrypt(ciphertext, plaintext, length, key, iv, cipher);
}
