#include "macos_fuse.h"
#include <stdio.h>
#include <stdlib.h>

static void usage(void)
{
    fprintf(stderr, "Usage: bitlocker-mount <volume> <mountpoint>\n");
    exit(EXIT_FAILURE);
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        usage();
    }

    const char *volume_path = argv[1];
    const char *mount_point = argv[2];

    if (!bitlocker_mount_volume(volume_path, mount_point)) {
        fprintf(stderr, "Failed to mount BitLocker volume\n");
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
