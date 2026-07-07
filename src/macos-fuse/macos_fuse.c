#include "macos_fuse.h"
#include "bitlocker_crypto.h"
#include <fuse.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * NOTE: fuse-t / macFUSE ship the FUSE 2.x API (see fuse.h: 2-arg getattr,
 * 4-arg fill_dir, 5-arg readdir). These handlers match that ABI. If this is
 * ever moved to libfuse3, the getattr/readdir signatures change.
 */

static int bitlocker_getattr(const char *path, struct stat *stbuf)
{
    memset(stbuf, 0, sizeof(struct stat));

    if (strcmp(path, "/") == 0) {
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
        return 0;
    }

    return -ENOENT;
}

static int bitlocker_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                             off_t offset, struct fuse_file_info *fi)
{
    (void)offset;
    (void)fi;

    if (strcmp(path, "/") != 0) {
        return -ENOENT;
    }

    filler(buf, ".", NULL, 0);
    filler(buf, "..", NULL, 0);
    return 0;
}

static int bitlocker_open(const char *path, struct fuse_file_info *fi)
{
    (void)path;
    (void)fi;
    return -ENOENT;
}

static int bitlocker_read(const char *path, char *buf, size_t size, off_t offset,
                          struct fuse_file_info *fi)
{
    (void)fi;
    (void)path;
    (void)offset;
    (void)size;
    (void)buf;

    return -ENOENT;
}

static const struct fuse_operations bitlocker_ops = {
    .getattr = bitlocker_getattr,
    .readdir = bitlocker_readdir,
    .open = bitlocker_open,
    .read = bitlocker_read,
};

bool bitlocker_mount_volume(const char *volume_path, const char *mount_point)
{
    if (!volume_path || !mount_point) {
        return false;
    }

    char *fuse_argv[] = {
        "bitlocker-mount",
        (char *)mount_point,
        "-f",
    };
    int fuse_argc = 3;

    printf("Mounting BitLocker volume '%s' at '%s'\n", volume_path, mount_point);

    bitlocker_crypto_init();

    int status = fuse_main(fuse_argc, fuse_argv, &bitlocker_ops, NULL);
    return status == 0;
}
