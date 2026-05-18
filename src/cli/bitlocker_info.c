#include "bitlocker_crypto.h"
#include <stdio.h>
#include <stdlib.h>

static void usage(void)
{
    fprintf(stderr, "Usage: bitlocker-info <volume>\n");
    exit(EXIT_FAILURE);
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        usage();
    }

    const char *volume_path = argv[1];
    printf("Inspecting BitLocker volume: %s\n", volume_path);
    printf("TODO: parse header and print metadata\n");

    /* TODO: add BitLocker header parsing and algorithm reporting */
    (void)bitlocker_crypto_init();

    return EXIT_SUCCESS;
}
