#include "bitlocker_crypto.h"
#include <stdio.h>
#include <stdlib.h>

static void usage(void)
{
    fprintf(stderr, "Usage: bitlocker-decrypt <volume> <output-directory>\n");
    exit(EXIT_FAILURE);
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        usage();
    }

    const char *volume_path = argv[1];
    const char *output_dir = argv[2];

    printf("Decrypting volume %s to %s\n", volume_path, output_dir);
    bitlocker_crypto_init();

    /* TODO: implement full volume decryption and NTFS export */
    return EXIT_SUCCESS;
}
