#ifndef MACOS_FUSE_H
#define MACOS_FUSE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

bool bitlocker_mount_volume(const char *volume_path, const char *mount_point);

#ifdef __cplusplus
}
#endif

#endif // MACOS_FUSE_H
