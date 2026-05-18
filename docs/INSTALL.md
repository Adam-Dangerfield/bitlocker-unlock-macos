# Installation

## Requirements

- macOS 10.13+
- CMake 3.15+
- macFUSE or FUSE-T
- OpenSSL
- ntfs-3g (for NTFS file access)

## Build

```bash
brew install cmake openssl@3 macfuse ntfs-3g
mkdir -p build
cd build
cmake .. -DCMAKE_PREFIX_PATH="$(brew --prefix openssl@3)"
cmake --build .
```

## Run

```bash
./src/cli/bitlocker-mount /dev/disk2s1 /Volumes/bitlocker
```
