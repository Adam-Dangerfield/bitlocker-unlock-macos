#include "bitlocker_crypto.h"
#include <stdio.h>
#include <string.h>

int main(void)
{
    if (!bitlocker_crypto_init()) {
        fprintf(stderr, "crypto init failed\n");
        return 1;
    }

    const uint8_t ciphertext[16] = {0};
    uint8_t plaintext[16] = {0};
    const uint8_t key[16] = {0};
    const uint8_t iv[16] = {0};

    int result = bitlocker_decrypt_sector(ciphertext, plaintext, sizeof(ciphertext), key, iv, BITLOCKER_ALGO_AES_CBC);
    if (result < 0) {
        fprintf(stderr, "aes decrypt stub failed\n");
        return 1;
    }

    printf("crypto stub test passed\n");
    return 0;
}
